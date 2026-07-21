import Foundation
import CircuiteFoundation
import ToolQualification

public struct DefaultFlowOrchestrator: Sendable {
    private let infrastructure: any FlowRunInfrastructure
    private let ledgerCoordinator: FlowRunLedgerCoordinator
    private let evaluator: ToolTrustEvaluator
    private let progressStore: FlowRunProgressStore
    private let producer: ProducerIdentity
    private let stageResultValidator: any FlowStageResultValidating

    public init(
        infrastructure: any FlowRunInfrastructure,
        ledgerPersistence: any FlowRunLedgerPersisting,
        producer: ProducerIdentity,
        evaluator: ToolTrustEvaluator = ToolTrustEvaluator(),
        progressStore: FlowRunProgressStore,
        stageResultValidator: any FlowStageResultValidating = DefaultFlowStageResultValidator()
    ) {
        self.infrastructure = infrastructure
        self.ledgerCoordinator = FlowRunLedgerCoordinator(persistence: ledgerPersistence)
        self.producer = producer
        self.evaluator = evaluator
        self.progressStore = progressStore
        self.stageResultValidator = stageResultValidator
    }

    private enum PersistedApprovalResolution {
        case none
        case approved(FlowStageResult)
        case blocked(FlowStageResult)
        case rejected(FlowStageResult)
    }

    public func run(
        request: FlowOperationRequest,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult],
        executors: [any FlowStageExecutor],
        artifactPreparer: (any FlowRunArtifactPreparing)? = nil
    ) async throws -> FlowRunResult {
        let runStartedAt = Date()
        try validate(request: request)
        let executorsByStageID = try indexExecutors(executors)
        try validateExecutorCoverage(request: request, executorsByStageID: executorsByStageID)

        try await infrastructure.prepareRun(
            runID: request.runID,
            requireNew: !request.allowExistingRun
        )
        let createdRun = !request.allowExistingRun
        var setupArtifacts: [ArtifactReference] = []
        if request.allowExistingRun {
            _ = try await ledgerCoordinator.load(runID: request.runID)
        } else {
            let now = Date()
            let manifest = try FlowRunManifest(
                runID: request.runID,
                status: .created,
                actor: request.actor,
                intent: request.intent,
                createdAt: now,
                updatedAt: now
            )
            try await ledgerCoordinator.create(
                FlowRunLedger(
                    runID: request.runID,
                    runManifest: manifest,
                    plan: FlowRunPlan(
                        runID: request.runID,
                        intent: request.intent,
                        toolchainProfile: request.toolchainProfile,
                        stages: request.stages
                    ),
                    stages: []
                )
            )
        }
        var planReference: ArtifactReference
        var preparedRunArtifacts: [ArtifactReference] = []
        do {
            if let artifactPreparer {
                let preparedArtifacts = try await artifactPreparer.prepareArtifacts(
                    runID: request.runID,
                    workspaceID: request.workspaceID
                )
                for artifact in preparedArtifacts {
                    let integrity = await infrastructure.verifyArtifact(artifact)
                    guard integrity.isVerified else {
                        throw FlowExecutionError.runArtifactIntegrityFailure(
                            artifactID: artifact.id.rawValue,
                            issues: integrity.issues.map { $0.code.rawValue }
                        )
                    }
                }
                preparedRunArtifacts = preparedArtifacts
                setupArtifacts = try mergedArtifactReferences(
                    setupArtifacts + preparedArtifacts
                )
            }
            planReference = try await persistRunPlan(
                request: request,
                workspaceID: request.workspaceID
            )
            _ = try await ledgerCoordinator.transition(
                runID: request.runID,
                to: .running,
                registering: preparedRunArtifacts + [planReference]
            )
            planReference = try await retainedRunPlanReference(for: request)
            try await progressStore.appendEvent(
                runID: request.runID,
                kind: .runStarted,
                runStatus: .running,
                message: "Run \(request.runID) started."
            )
        } catch {
            let setupError = error
            guard createdRun else {
                throw setupError
            }
            do {
                try await finalizeSetupFailure(
                    request: request,
                    runStartedAt: runStartedAt,
                    preparedArtifacts: setupArtifacts,
                    error: setupError
                )
            } catch {
                throw FlowExecutionError.setupFailureTerminalizationFailed(
                    setup: FlowFailureContext(capturing: setupError),
                    terminalization: FlowFailureContext(capturing: error)
                )
            }
            throw setupError
        }
        let makeResult: (FlowRunStatus, [FlowStageResult]) throws -> FlowRunResult = { status, stages in
            let provenance = try ExecutionProvenance(
                producer: producer,
                inputs: [planReference],
                startedAt: runStartedAt,
                completedAt: Date()
            )
            return try FlowRunResult(
                runID: request.runID,
                status: status,
                stages: stages,
                provenance: provenance
            )
        }
        let context = FlowExecutionContext(
            workspaceID: request.workspaceID,
            runID: request.runID,
            infrastructure: infrastructure,
            toolRegistry: toolRegistry,
            healthResults: healthResults
        )
        var stageResults: [FlowStageResult] = []
        var toolchainRecords: [FlowToolchainStageRecord] = []
        var activeStageID: String?

        do {
        for stage in request.stages {
            activeStageID = stage.stageID
            guard let executor = executorsByStageID[stage.stageID] else {
                throw FlowExecutionError.missingExecutor(stage.stageID)
            }
            let configuredToolchainRecord = FlowToolchainStageRecord(
                stageID: stage.stageID,
                executorToolID: executor.toolID,
                requiredTool: stage.requiredTool
            )
            if let cancellation = try await progressStore.loadCancellationRequest(
                runID: request.runID,
            ) {
                let diagnostics = cancellationDiagnostics(cancellation)
                let blocked = blockedStageResult(
                    stageID: stage.stageID,
                    diagnostics: diagnostics,
                    gateID: "cancellation"
                )
                try await persistStageResult(
                    blocked,
                    runID: request.runID,
                    workspaceID: request.workspaceID
                )
                stageResults.append(blocked)
                toolchainRecords.append(configuredToolchainRecord)
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .cancellationObserved,
                    stageID: stage.stageID,
                    stageStatus: .blocked,
                    runStatus: .cancelled,
                    message: "Run cancellation observed before stage \(stage.stageID)."
                )
                let result = try makeResult(.cancelled, stageResults)
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .runFinished,
                    runStatus: .cancelled,
                    message: "Run \(request.runID) cancelled."
                )
                try await persistRunResult(
                    result,
                    workspaceID: request.workspaceID,
                    toolchainProfile: request.toolchainProfile,
                    toolchainRecords: toolchainRecords
                )
                return result
            }

            if request.allowExistingRun,
               !stage.requiresApproval,
               let persisted = try await reusableStageResult(
                   for: stage,
                   runID: request.runID
            ) {
                stageResults.append(persisted)
                toolchainRecords.append(configuredToolchainRecord)
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: progressKind(for: persisted.status),
                    stageID: stage.stageID,
                    stageStatus: persisted.status,
                    runStatus: aggregateStatus(stageResults),
                    message: "Stage \(stage.stageID) reused its persisted successful result during resume."
                )
                continue
            }

            if stage.requiresApproval {
                switch try await persistedApprovalResolution(
                    for: stage,
                    request: request,
                    planReference: planReference,
                    executor: executorsByStageID[stage.stageID],
                    context: context
                ) {
                case .none:
                    break
                case .approved(let result):
                    try await persistStageResult(
                        result,
                        runID: request.runID,
                        workspaceID: request.workspaceID
                    )
                    stageResults.append(result)
                    toolchainRecords.append(configuredToolchainRecord)
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: progressKind(for: result.status),
                        stageID: stage.stageID,
                        stageStatus: result.status,
                        runStatus: aggregateStatus(stageResults),
                        message: "Stage \(stage.stageID) resumed from a content-bound approval."
                    )
                    continue
                case .blocked(let result):
                    try await persistStageResult(
                        result,
                        runID: request.runID,
                        workspaceID: request.workspaceID
                    )
                    stageResults.append(result)
                    toolchainRecords.append(configuredToolchainRecord)
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .stageBlocked,
                        stageID: stage.stageID,
                        stageStatus: result.status,
                        runStatus: .blocked,
                        message: "Stage \(stage.stageID) blocked because its approval binding is stale."
                    )
                    let runResult = try makeResult(.blocked, stageResults)
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .runFinished,
                        runStatus: .blocked,
                        message: "Run \(request.runID) blocked."
                    )
                    try await persistRunResult(
                        runResult,
                        workspaceID: request.workspaceID,
                        toolchainProfile: request.toolchainProfile,
                        toolchainRecords: toolchainRecords
                    )
                    return runResult
                case .rejected(let result):
                    try await persistStageResult(
                        result,
                        runID: request.runID,
                        workspaceID: request.workspaceID
                    )
                    stageResults.append(result)
                    toolchainRecords.append(configuredToolchainRecord)
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: progressKind(for: result.status),
                        stageID: stage.stageID,
                        stageStatus: result.status,
                        runStatus: .failed,
                        message: "Stage \(stage.stageID) failed because its approval was rejected."
                    )
                    let runResult = try makeResult(.failed, stageResults)
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .runFinished,
                        runStatus: .failed,
                        message: "Run \(request.runID) failed."
                    )
                    try await persistRunResult(
                        runResult,
                        workspaceID: request.workspaceID,
                        toolchainProfile: request.toolchainProfile,
                        toolchainRecords: toolchainRecords
                    )
                    return runResult
                }
            }

            var preExecutionGates: [FlowGateResult] = []
            var toolchainRecord = configuredToolchainRecord

            if let requiredTool = stage.requiredTool {
                let evaluatedTools = await evaluatedToolDecisions(
                    requirement: requiredTool,
                    toolRegistry: toolRegistry,
                    healthResults: healthResults
                )
                toolchainRecord.evaluations = evaluatedTools.map { evaluated in
                    FlowToolchainEvaluationRecord(
                        descriptor: evaluated.descriptor,
                        decision: evaluated.decision,
                        health: healthResults[evaluated.descriptor.toolID]
                    )
                }
                // The trust verdict must describe the tool that actually
                // executes the stage: when several registered tools are
                // eligible for the same operation, the stage executor's
                // own tool outranks the generic ordering. Otherwise a
                // capability shared across tools would deterministically
                // select a non-executing tool and block every such stage
                // with EXECUTOR_TOOL_MISMATCH.
                let eligibleTools = evaluatedTools.filter { $0.decision.status == .eligible }
                let selectedTool = eligibleTools.first { $0.descriptor.toolID == executor.toolID }
                    ?? eligibleTools.first
                guard let selectedTool else {
                    toolchainRecords.append(toolchainRecord)
                    let diagnostics = noEligibleToolDiagnostics(evaluatedTools)
                    let blocked = blockedStageResult(
                        stageID: stage.stageID,
                        diagnostics: diagnostics,
                        gateID: "tool-trust"
                    )
                    try await persistStageResult(
                        blocked,
                        runID: request.runID,
                        workspaceID: request.workspaceID
                    )
                    stageResults.append(blocked)
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .stageBlocked,
                        stageID: stage.stageID,
                        stageStatus: .blocked,
                        runStatus: .blocked,
                        message: "Stage \(stage.stageID) blocked before execution."
                    )
                    let result = try makeResult(.blocked, stageResults)
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .runFinished,
                        runStatus: .blocked,
                        message: "Run \(request.runID) blocked."
                    )
                    try await persistRunResult(
                        result,
                        workspaceID: request.workspaceID,
                        toolchainProfile: request.toolchainProfile,
                        toolchainRecords: toolchainRecords
                    )
                    return result
                }
                toolchainRecord.selectedToolID = selectedTool.descriptor.toolID
                toolchainRecord.selectedDescriptor = selectedTool.descriptor
                toolchainRecord.selectedDecision = selectedTool.decision
                toolchainRecord.selectedHealth = healthResults[selectedTool.descriptor.toolID]

                guard selectedTool.descriptor.toolID == executor.toolID else {
                    toolchainRecords.append(toolchainRecord)
                    let diagnostics = [
                        FlowDiagnostic(
                            severity: .error,
                            code: "EXECUTOR_TOOL_MISMATCH",
                            message: "Selected tool \(selectedTool.descriptor.toolID) does not match executor tool \(executor.toolID)."
                        ),
                    ]
                    let blocked = blockedStageResult(
                        stageID: stage.stageID,
                        diagnostics: diagnostics,
                        gateID: "tool-trust"
                    )
                    try await persistStageResult(
                        blocked,
                        runID: request.runID,
                        workspaceID: request.workspaceID
                    )
                    stageResults.append(blocked)
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .stageBlocked,
                        stageID: stage.stageID,
                        stageStatus: .blocked,
                        runStatus: .blocked,
                        message: "Stage \(stage.stageID) blocked by executor/tool mismatch."
                    )
                    let result = try makeResult(.blocked, stageResults)
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .runFinished,
                        runStatus: .blocked,
                        message: "Run \(request.runID) blocked."
                    )
                    try await persistRunResult(
                        result,
                        workspaceID: request.workspaceID,
                        toolchainProfile: request.toolchainProfile,
                        toolchainRecords: toolchainRecords
                    )
                    return result
                }

                preExecutionGates.append(toolTrustGate(
                    selectedTool: selectedTool.descriptor,
                    decision: selectedTool.decision
                ))
            }
            toolchainRecords.append(toolchainRecord)

            let stageOutcome: FlowStageExecutionOutcome
            do {
                stageOutcome = try await executeStageWithRetry(
                    stage: stage,
                    executor: executor,
                    context: context,
                    request: request,
                    planReference: planReference,
                    preExecutionGates: preExecutionGates
                )
            } catch let error as FlowExecutionError where Self.isStageResultContractFailure(error) {
                let failed = failedStageResult(
                    stageID: stage.stageID,
                    code: "STAGE_RESULT_REJECTED",
                    message: error.localizedDescription
                )
                try await persistStageResult(
                    failed,
                    runID: request.runID,
                    workspaceID: request.workspaceID
                )
                stageResults.append(failed)
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .stageFailed,
                    stageID: stage.stageID,
                    stageStatus: .failed,
                    runStatus: .failed,
                    message: "Stage \(stage.stageID) produced an invalid result."
                )
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .runFinished,
                    runStatus: .failed,
                    message: "Run \(request.runID) failed because a stage result was rejected."
                )
                let failedRun = try makeResult(.failed, stageResults)
                try await persistRunResult(
                    failedRun,
                    workspaceID: request.workspaceID,
                    toolchainProfile: request.toolchainProfile,
                    toolchainRecords: toolchainRecords
                )
                throw error
            }
            let result = stageOutcome.result
            try await persistStageResult(
                result,
                runID: request.runID,
                workspaceID: request.workspaceID
            )
            stageResults.append(result)

            if stageOutcome.runStatusOverride == .cancelled {
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .cancellationObserved,
                    stageID: stage.stageID,
                    stageStatus: .blocked,
                    runStatus: .cancelled,
                    message: "Run cancellation observed during stage \(stage.stageID)."
                )
                let runResult = try makeResult(.cancelled, stageResults)
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .runFinished,
                    runStatus: .cancelled,
                    message: "Run \(request.runID) cancelled."
                )
                try await persistRunResult(
                    runResult,
                    workspaceID: request.workspaceID,
                    toolchainProfile: request.toolchainProfile,
                    toolchainRecords: toolchainRecords
                )
                return runResult
            }
            try await progressStore.appendEvent(
                runID: request.runID,
                kind: progressKind(for: result.status),
                stageID: stage.stageID,
                stageStatus: result.status,
                runStatus: aggregateStatus(stageResults),
                message: "Stage \(stage.stageID) finished with status \(result.status.rawValue)."
            )

            if result.status == .failed || result.status == .blocked {
                let runStatus = aggregateStatus(stageResults)
                let runResult = try makeResult(runStatus, stageResults)
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .runFinished,
                    runStatus: runStatus,
                    message: "Run \(request.runID) finished with status \(runStatus.rawValue)."
                )
                try await persistRunResult(
                    runResult,
                    workspaceID: request.workspaceID,
                    toolchainProfile: request.toolchainProfile,
                    toolchainRecords: toolchainRecords
                )
                return runResult
            }
        }

        let runResult = try makeResult(aggregateStatus(stageResults), stageResults)
        try await progressStore.appendEvent(
            runID: request.runID,
            kind: .runFinished,
            runStatus: runResult.status,
            message: "Run \(request.runID) finished with status \(runResult.status.rawValue)."
        )
        try await persistRunResult(
            runResult,
            workspaceID: request.workspaceID,
            toolchainProfile: request.toolchainProfile,
            toolchainRecords: toolchainRecords
        )
        return runResult
        } catch {
            let executionError = error
            do {
                try await finalizeExecutionFailure(
                    request: request,
                    runStartedAt: runStartedAt,
                    activeStageID: activeStageID,
                    completedStages: stageResults,
                    toolchainRecords: toolchainRecords,
                    error: executionError
                )
            } catch {
                throw FlowExecutionError.executionFailureTerminalizationFailed(
                    execution: FlowFailureContext(capturing: executionError),
                    terminalization: FlowFailureContext(capturing: error)
                )
            }
            throw executionError
        }
    }

    private func executeStageWithRetry(
        stage: FlowStageDefinition,
        executor: any FlowStageExecutor,
        context: FlowExecutionContext,
        request: FlowOperationRequest,
        planReference: ArtifactReference,
        preExecutionGates: [FlowGateResult]
    ) async throws -> FlowStageExecutionOutcome {
        var attempts: [FlowStageAttemptRecord] = []
        var attemptIndex = 1
        let maxAttempts = stage.retryPolicy.maxAttempts

        while attemptIndex <= maxAttempts {
            let startedAt = Date()
            try await progressStore.appendEvent(
                runID: request.runID,
                kind: .stageStarted,
                stageID: stage.stageID,
                stageStatus: .running,
                runStatus: .running,
                message: "Stage \(stage.stageID) attempt \(attemptIndex) of \(maxAttempts) started."
            )

            var attemptResult: FlowStageResult
            var cancelled = false
            do {
                attemptResult = try await executor.execute(stage: stage, context: context)
            } catch let cancellationError as FlowRunCancellationError {
                cancelled = true
                attemptResult = blockedStageResult(
                    stageID: stage.stageID,
                    diagnostics: cancellationDiagnostics(cancellationError.request),
                    gateID: "cancellation"
                )
            } catch {
                attemptResult = failedStageResult(
                    stageID: stage.stageID,
                    code: "STAGE_EXECUTOR_FAILED",
                    message: diagnosticMessage(for: error)
                )
            }

            attemptResult.gates.insert(contentsOf: preExecutionGates, at: 0)
            attemptResult.diagnostics.append(contentsOf: preExecutionGates.flatMap(\.diagnostics))
            if stage.requiresApproval {
                attemptResult = try await applyApprovalGate(
                    to: attemptResult,
                    request: request,
                    planReference: planReference
                )
            }

            let finishedAt = Date()
            let decision = retryDecision(
                for: attemptResult,
                policy: stage.retryPolicy,
                attemptIndex: attemptIndex,
                cancellationObserved: cancelled
            )
            attempts.append(
                FlowStageAttemptRecord(
                    stageID: stage.stageID,
                    attemptIndex: attemptIndex,
                    maxAttempts: maxAttempts,
                    status: attemptResult.status,
                    diagnosticCodes: diagnosticCodes(from: attemptResult),
                    retryDecision: decision,
                    startedAt: startedAt,
                    finishedAt: finishedAt
                )
            )

            if decision.shouldRetry {
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .stageRetryScheduled,
                    stageID: stage.stageID,
                    stageStatus: attemptResult.status,
                    runStatus: .running,
                    message: "Stage \(stage.stageID) retry scheduled after attempt \(attemptIndex)."
                )
                attemptIndex += 1
                continue
            }

            let finalResult = try await attachAttemptRecordsIfNeeded(
                attempts,
                to: attemptResult,
                stage: stage,
                request: request
            )
            try await validateStageResult(finalResult, expectedStageID: stage.stageID)
            return FlowStageExecutionOutcome(
                result: finalResult,
                runStatusOverride: cancelled ? .cancelled : nil
            )
        }

        var failed = failedStageResult(
            stageID: stage.stageID,
            code: "RETRY_POLICY_EXHAUSTED",
            message: "Retry policy exhausted before a final stage result was produced."
        )
        failed.attempts = attempts
        return FlowStageExecutionOutcome(result: failed)
    }

    private func evaluatedToolDecisions(
        requirement: ToolTrustRequirement,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult]
    ) async -> [(descriptor: ToolDescriptor, decision: ToolTrustDecision)] {
        var decisions: [(descriptor: ToolDescriptor, decision: ToolTrustDecision)] = []
        for descriptor in toolRegistry.descriptors.values {
            let decision = await evaluator.evaluate(
                descriptor: descriptor,
                requirement: requirement,
                health: healthResults[descriptor.toolID],
                artifactReader: infrastructure
            )
            decisions.append((descriptor, decision))
        }
        return decisions.sorted { lhs, rhs in
                if lhs.decision.status != rhs.decision.status {
                    return lhs.decision.status == .eligible
                }
                if lhs.descriptor.trustProfile.level != rhs.descriptor.trustProfile.level {
                    return lhs.descriptor.trustProfile.level > rhs.descriptor.trustProfile.level
                }
                return lhs.descriptor.toolID < rhs.descriptor.toolID
            }
    }

    private func toolTrustGate(
        selectedTool: ToolDescriptor,
        decision: ToolTrustDecision
    ) -> FlowGateResult {
        let selectedDiagnostic = FlowDiagnostic(
            severity: .info,
            code: "TOOL_SELECTED",
            message: "Selected tool \(selectedTool.toolID) at \(selectedTool.trustProfile.level.rawValue) qualification."
        )
        return FlowGateResult(
            gateID: "tool-trust",
            status: .passed,
            diagnostics: [selectedDiagnostic] + decision.diagnostics.map { flowDiagnostic($0) }
        )
    }

    private func noEligibleToolDiagnostics(
        _ evaluatedTools: [(descriptor: ToolDescriptor, decision: ToolTrustDecision)]
    ) -> [FlowDiagnostic] {
        let base = FlowDiagnostic(
            severity: .error,
            code: "NO_ELIGIBLE_TOOL",
            message: "No registered tool satisfies the stage trust requirement."
        )
        let toolDiagnostics = evaluatedTools.flatMap { evaluated in
            evaluated.decision.diagnostics.map { diagnostic in
                flowDiagnostic(
                    diagnostic,
                    messagePrefix: "\(evaluated.descriptor.toolID): "
                )
            }
        }
        return [base] + toolDiagnostics
    }

    private func flowDiagnostic(
        _ diagnostic: ToolDiagnostic,
        messagePrefix: String = ""
    ) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: flowSeverity(diagnostic.severity),
            code: diagnostic.code,
            message: messagePrefix + diagnostic.message
        )
    }

    private func flowSeverity(_ severity: ToolDiagnosticSeverity) -> FlowDiagnosticSeverity {
        switch severity {
        case .info:
            .info
        case .warning:
            .warning
        case .error:
            .error
        }
    }

    private func persistedApprovalResolution(
        for stage: FlowStageDefinition,
        request: FlowOperationRequest,
        planReference: ArtifactReference,
        executor: (any FlowStageExecutor)?,
        context: FlowExecutionContext
    ) async throws -> PersistedApprovalResolution {
        guard let record = try await infrastructure.loadApproval(
            runID: request.runID,
            stageID: stage.stageID
        ) else {
            return .none
        }

        switch record.verdict {
        case .rejected:
            return .rejected(rejectedStageResult(stageID: stage.stageID, record: record))
        case .approved, .waived:
            guard let reviewedResult = try await loadPersistedStageResult(
                stageID: stage.stageID,
                runID: request.runID
            ) else {
                let diagnostic = FlowDiagnostic(
                    severity: .error,
                    code: "APPROVAL_REVIEW_INPUT_MISSING",
                    message: "Approved stage \(stage.stageID) is missing its reviewed result."
                )
                return .blocked(approvalBindingBlockedStageResult(stageID: stage.stageID, diagnostic: diagnostic))
            }
            if isApprovalApplied(to: reviewedResult) {
                let approvalInputContent: Data
                do {
                    approvalInputContent = try await infrastructure.loadArtifactContent(
                        for: record.evidence.stageResult
                    )
                } catch {
                    let diagnostic = FlowDiagnostic(
                        severity: .error,
                        code: "APPROVAL_REVIEW_INPUT_MISSING",
                        message: "Approved stage \(stage.stageID) is missing the immutable reviewed result required for resume."
                    )
                    return .blocked(approvalBindingBlockedStageResult(stageID: stage.stageID, diagnostic: diagnostic))
                }
                if let diagnostic = approvalBindingDiagnostic(
                    record: record,
                    planReference: planReference,
                    resultContent: approvalInputContent
                ) {
                    return .blocked(approvalBindingBlockedStageResult(stageID: stage.stageID, diagnostic: diagnostic))
                }
                return .approved(reviewedResult)
            }
            if let diagnostic = approvalBindingDiagnostic(
                record: record,
                planReference: planReference,
                stageResult: reviewedResult
            ) {
                return .blocked(approvalBindingBlockedStageResult(stageID: stage.stageID, diagnostic: diagnostic))
            }
            guard reviewedResult.stageID == stage.stageID else {
                let diagnostic = FlowDiagnostic(
                    severity: .error,
                    code: "APPROVAL_BINDING_MISMATCH",
                    message: "Approval targets stage \(stage.stageID), but the reviewed result belongs to \(reviewedResult.stageID). Re-approval is required."
                )
                return .blocked(approvalBindingBlockedStageResult(stageID: stage.stageID, diagnostic: diagnostic))
            }
            if let validator = executor as? any FlowStageApprovalValidating {
                do {
                    let diagnostics = try await validator.validateApproval(
                        record,
                        reviewedResult: reviewedResult,
                        context: context
                    )
                    if !diagnostics.isEmpty {
                        return .blocked(
                            approvalValidationBlockedStageResult(
                                stageID: stage.stageID,
                                diagnostics: diagnostics
                            )
                        )
                    }
                } catch {
                    let diagnostic = FlowDiagnostic(
                        severity: .error,
                        code: "APPROVAL_DOMAIN_VALIDATION_ERROR",
                        message: "Approval domain validation failed: \(error.localizedDescription). Re-approval is required."
                    )
                    return .blocked(
                        approvalValidationBlockedStageResult(
                            stageID: stage.stageID,
                            diagnostics: [diagnostic]
                        )
                    )
                }
            }
            return .approved(approvedStageResult(from: reviewedResult, record: record))
        }
    }

    private func approvalBindingDiagnostic(
        record: FlowApprovalRecord,
        planReference: ArtifactReference,
        resultContent: Data
    ) -> FlowDiagnostic? {
        guard planReference == record.evidence.plan else {
            return FlowDiagnostic(
                severity: .error,
                code: "APPROVAL_BINDING_MISMATCH",
                message: "Approval for \(record.stageID) was recorded for a different plan.json. Re-approval is required."
            )
        }

        do {
            let actualSHA256 = try SHA256ContentDigester()
                .digest(data: resultContent)
                .hexadecimalValue
            let actualByteCount = UInt64(resultContent.count)
            guard actualSHA256 == record.evidence.stageResult.digest.hexadecimalValue,
                  actualByteCount == record.evidence.stageResult.byteCount else {
                return FlowDiagnostic(
                    severity: .error,
                    code: "APPROVAL_BINDING_MISMATCH",
                    message: "Approval for \(record.stageID) was recorded for a different stage result. Re-approval is required."
                )
            }
            return nil
        } catch {
            return FlowDiagnostic(
                severity: .error,
                code: "APPROVAL_BINDING_MISMATCH",
                message: "Approval for \(record.stageID) could not verify the reviewed stage result: \(error.localizedDescription)"
            )
        }
    }

    private func isApprovalApplied(to result: FlowStageResult) -> Bool {
        result.status == .succeeded
            && result.gates.contains {
                $0.gateID == "approval" && $0.status == .passed
            }
    }

    private func approvalBindingDiagnostic(
        record: FlowApprovalRecord,
        planReference: ArtifactReference,
        stageResult: FlowStageResult
    ) -> FlowDiagnostic? {
        guard planReference == record.evidence.plan else {
            return FlowDiagnostic(
                severity: .error,
                code: "APPROVAL_BINDING_MISMATCH",
                message: "Approval for \(record.stageID) was recorded for a different plan.json. Re-approval is required."
            )
        }
        guard stageResult.stageID == record.stageID else {
            return FlowDiagnostic(
                severity: .error,
                code: "APPROVAL_BINDING_MISMATCH",
                message: "Approval targets stage \(record.stageID), but the current result belongs to \(stageResult.stageID). Re-approval is required."
            )
        }
        do {
            let data = try encodedPackageJSON(stageResult)
            let actualSHA256 = try SHA256ContentDigester()
                .digest(data: data)
                .hexadecimalValue
            let actualByteCount = UInt64(data.count)
            guard actualSHA256 == record.evidence.stageResult.digest.hexadecimalValue,
                  actualByteCount == record.evidence.stageResult.byteCount else {
                return FlowDiagnostic(
                    severity: .error,
                    code: "APPROVAL_BINDING_MISMATCH",
                    message: "Approval for \(record.stageID) was recorded for a different stage result. Re-approval is required."
                )
            }
            return nil
        } catch {
            return FlowDiagnostic(
                severity: .error,
                code: "APPROVAL_BINDING_MISMATCH",
                message: "Approval for \(record.stageID) could not verify the current stage result: \(error.localizedDescription)"
            )
        }
    }

    private func encodedPackageJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func approvalBindingBlockedStageResult(
        stageID: String,
        diagnostic: FlowDiagnostic
    ) -> FlowStageResult {
        FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: [diagnostic],
            gates: [
                FlowGateResult(
                    gateID: "approval",
                    status: .incomplete,
                    diagnostics: [diagnostic]
                ),
            ]
        )
    }

    private func approvalValidationBlockedStageResult(
        stageID: String,
        diagnostics: [FlowDiagnostic]
    ) -> FlowStageResult {
        FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: diagnostics,
            gates: [
                FlowGateResult(
                    gateID: "approval",
                    status: .incomplete,
                    diagnostics: diagnostics
                ),
            ]
        )
    }

    private func approvedStageResult(
        from result: FlowStageResult,
        record: FlowApprovalRecord
    ) -> FlowStageResult {
        var updated = result
        updated.status = .succeeded
        updated.gates.removeAll { $0.gateID == "approval" }
        updated.diagnostics.removeAll { approvalGateDiagnosticCodes.contains($0.code) }
        let diagnostic = acceptedApprovalDiagnostic(record)
        let gateStatus: FlowGateStatus = record.verdict == .waived ? .waived : .passed
        updated.gates.append(FlowGateResult(gateID: "approval", status: gateStatus, diagnostics: [diagnostic]))
        updated.diagnostics.append(diagnostic)
        return updated
    }

    private func rejectedStageResult(
        stageID: String,
        record: FlowApprovalRecord
    ) -> FlowStageResult {
        let diagnostic = rejectedDiagnostic(record)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [
                FlowGateResult(gateID: "approval", status: .failed, diagnostics: [diagnostic]),
            ]
        )
    }

    private var approvalGateDiagnosticCodes: Set<String> {
        [
            "APPROVAL_PENDING",
            "APPROVAL_BINDING_MISSING",
            "APPROVAL_BINDING_MISMATCH",
            "STAGE_APPROVED",
            "STAGE_WAIVED",
            "STAGE_REJECTED",
        ]
    }

    private func approvedDiagnostic(_ record: FlowApprovalRecord) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: .info,
            code: "STAGE_APPROVED",
            message: "Approved by \(record.reviewer)\(record.note.isEmpty ? "" : ": \(record.note)")."
        )
    }

    private func waivedDiagnostic(_ record: FlowApprovalRecord) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: .warning,
            code: "STAGE_WAIVED",
            message: "Waived by \(record.reviewer): \(record.note)."
        )
    }

    private func acceptedApprovalDiagnostic(_ record: FlowApprovalRecord) -> FlowDiagnostic {
        record.verdict == .waived ? waivedDiagnostic(record) : approvedDiagnostic(record)
    }

    private func rejectedDiagnostic(_ record: FlowApprovalRecord) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: .error,
            code: "STAGE_REJECTED",
            message: "Rejected by \(record.reviewer)\(record.note.isEmpty ? "" : ": \(record.note)")."
        )
    }

    /// Judges the stage's "approval" gate from the run ledger's
    /// `approvals/{stageID}.json` record. The decision only matters on a
    /// stage that otherwise succeeded: approved keeps it succeeded,
    /// rejected fails it, and an absent record BLOCKS the run until the
    /// review cockpit records one — re-running the same runID then
    /// resumes past the gate.
    private func applyApprovalGate(
        to result: FlowStageResult,
        request: FlowOperationRequest,
        planReference: ArtifactReference
    ) async throws -> FlowStageResult {
        var updated = result
        guard result.status == .succeeded else { return result }

        let record = try await infrastructure.loadApproval(
            runID: request.runID,
            stageID: result.stageID
        )
        guard let record else {
            let diagnostic = FlowDiagnostic(
                severity: .warning,
                code: "APPROVAL_PENDING",
                message: "Stage awaits human approval (approvals/\(result.stageID).json)."
            )
            updated.gates.append(FlowGateResult(
                gateID: "approval",
                status: .incomplete,
                diagnostics: [diagnostic]
            ))
            updated.diagnostics.append(diagnostic)
            updated.status = .blocked
            return updated
        }
        switch record.verdict {
        case .approved, .waived:
            if let diagnostic = approvalBindingDiagnostic(
                record: record,
                planReference: planReference,
                stageResult: result
            ) {
                updated.gates.append(FlowGateResult(
                    gateID: "approval",
                    status: .incomplete,
                    diagnostics: [diagnostic]
                ))
                updated.diagnostics.append(diagnostic)
                updated.status = .blocked
                return updated
            }
            let diagnostic = acceptedApprovalDiagnostic(record)
            let gateStatus: FlowGateStatus = record.verdict == .waived ? .waived : .passed
            updated.gates.append(FlowGateResult(
                gateID: "approval",
                status: gateStatus,
                diagnostics: [diagnostic]
            ))
            updated.diagnostics.append(diagnostic)
        case .rejected:
            let diagnostic = rejectedDiagnostic(record)
            updated.gates.append(FlowGateResult(
                gateID: "approval",
                status: .failed,
                diagnostics: [diagnostic]
            ))
            updated.diagnostics.append(diagnostic)
            updated.status = .failed
        }
        return updated
    }

    private func validate(request: FlowOperationRequest) throws {
        let validator = FlowIdentifierValidator()
        try validator.validate(request.runID, kind: .runID)

        var stageIDs: Set<String> = []
        for stage in request.stages {
            try validator.validate(stage.stageID, kind: .stageID)
            guard stage.retryPolicy.maxAttempts >= 1 else {
                throw FlowExecutionError.invalidRetryPolicy(
                    stageID: stage.stageID,
                    maxAttempts: stage.retryPolicy.maxAttempts
                )
            }
            guard stageIDs.insert(stage.stageID).inserted else {
                throw FlowExecutionError.duplicateStageID(stage.stageID)
            }
        }
    }

    private func validateExecutorCoverage(
        request: FlowOperationRequest,
        executorsByStageID: [String: any FlowStageExecutor]
    ) throws {
        for stage in request.stages where executorsByStageID[stage.stageID] == nil {
            throw FlowExecutionError.missingExecutor(stage.stageID)
        }
    }

    private func indexExecutors(_ executors: [any FlowStageExecutor]) throws -> [String: any FlowStageExecutor] {
        let validator = FlowIdentifierValidator()
        var executorsByStageID: [String: any FlowStageExecutor] = [:]
        for executor in executors {
            try validator.validate(executor.stageID, kind: .stageID)
            do {
                try validator.validate(executor.toolID, kind: .toolID)
            } catch {
                throw FlowExecutionError.invalidExecutorToolID(stageID: executor.stageID, toolID: executor.toolID)
            }
            guard executorsByStageID[executor.stageID] == nil else {
                throw FlowExecutionError.duplicateExecutorStageID(executor.stageID)
            }
            executorsByStageID[executor.stageID] = executor
        }
        return executorsByStageID
    }

    private static func isStageResultContractFailure(_ error: FlowExecutionError) -> Bool {
        switch error {
        case .stageResultIdentifierMismatch, .invalidStageResult, .artifactIntegrityFailure:
            true
        case .missingExecutor, .duplicateStageID, .duplicateExecutorStageID,
             .invalidExecutorToolID, .invalidRetryPolicy, .duplicateRunID,
             .existingRunPlanMismatch, .missingArtifact, .invalidRunArtifactReference,
             .conflictingArtifactReference,
             .runArtifactIntegrityFailure,
             .setupFailureTerminalizationFailed, .executionFailureTerminalizationFailed:
            false
        }
    }

    private func aggregateStatus(_ stageResults: [FlowStageResult]) -> FlowRunStatus {
        if stageResults.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if stageResults.contains(where: { $0.status == .blocked }) {
            return .blocked
        }
        if stageResults.contains(where: { $0.status == .running || $0.status == .pending }) {
            return .running
        }
        if stageResults.allSatisfy({ $0.status == .succeeded || $0.status == .skipped }) {
            return .succeeded
        }
        return .partial
    }

    private func progressKind(for status: FlowStageStatus) -> FlowRunProgressEventKind {
        switch status {
        case .failed:
            .stageFailed
        case .blocked:
            .stageBlocked
        case .pending, .running, .succeeded, .skipped:
            .stageFinished
        }
    }

    private func retryDecision(
        for result: FlowStageResult,
        policy: FlowStageRetryPolicy,
        attemptIndex: Int,
        cancellationObserved: Bool
    ) -> FlowStageRetryDecision {
        if cancellationObserved {
            return FlowStageRetryDecision(
                shouldRetry: false,
                reason: .cancellationObserved
            )
        }
        guard result.status == .failed else {
            return FlowStageRetryDecision(
                shouldRetry: false,
                reason: .stageDidNotFail
            )
        }
        guard attemptIndex < policy.maxAttempts else {
            return FlowStageRetryDecision(
                shouldRetry: false,
                reason: .maxAttemptsReached
            )
        }
        guard policy.isEnabled else {
            return FlowStageRetryDecision(
                shouldRetry: false,
                reason: .notRetryable
            )
        }

        let retryableCodes = Set(policy.retryableDiagnosticCodes)
        let matchedCodes = diagnosticCodes(from: result)
            .filter { retryableCodes.contains($0) }
        guard !matchedCodes.isEmpty else {
            return FlowStageRetryDecision(
                shouldRetry: false,
                reason: .notRetryable
            )
        }
        return FlowStageRetryDecision(
            shouldRetry: true,
            reason: .retryableDiagnosticMatched,
            matchedDiagnosticCodes: Array(Set(matchedCodes)).sorted()
        )
    }

    private func attachAttemptRecordsIfNeeded(
        _ attempts: [FlowStageAttemptRecord],
        to result: FlowStageResult,
        stage: FlowStageDefinition,
        request: FlowOperationRequest
    ) async throws -> FlowStageResult {
        var updated = result
        updated.attempts = attempts
        guard stage.retryPolicy.isEnabled || attempts.count > 1 else {
            return updated
        }

        let reference = try await persistStageAttemptRecords(
            attempts,
            stageID: stage.stageID,
            runID: request.runID,
            workspaceID: request.workspaceID
        )
        updated.artifacts = try mergedArtifactReferences(updated.artifacts + [reference])
        return updated
    }

    private func persistStageAttemptRecords(
        _ attempts: [FlowStageAttemptRecord],
        stageID: String,
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws -> ArtifactReference {
        let relativePath = "runs/\(runID)/stages/\(stageID)/attempts.json"
        return try await persistJSONArtifact(
            attempts,
            path: relativePath,
            id: "\(stageID)-attempts",
            role: .output,
            kind: .other,
            format: .json,
            runID: runID,
            workspaceID: workspaceID,
            mode: .replaceable
        )
    }

    private func diagnosticCodes(from result: FlowStageResult) -> [String] {
        Array(Set((result.diagnostics + result.gates.flatMap(\.diagnostics)).map(\.code))).sorted()
    }

    private func persistStageResult(
        _ result: FlowStageResult,
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws {
        try stageResultValidator.validate(result, expectedStageID: result.stageID)
        _ = try await persistJSONArtifact(
            result,
            path: "runs/\(runID)/stages/\(result.stageID)/result.json",
            id: "\(result.stageID)-result",
            role: .output,
            kind: .other,
            format: .json,
            runID: runID,
            workspaceID: workspaceID,
            mode: .replaceable
        )
    }

    private func reusableStageResult(
        for stage: FlowStageDefinition,
        runID: String
    ) async throws -> FlowStageResult? {
        guard let result = try await loadPersistedStageResult(
            stageID: stage.stageID,
            runID: runID
        ) else { return nil }
        try await validateStageResult(result, expectedStageID: stage.stageID)
        guard result.status == .succeeded else {
            return nil
        }
        return result
    }

    private func loadPersistedStageResult(
        stageID: String,
        runID: String
    ) async throws -> FlowStageResult? {
        guard let artifact = try await loadPersistedStageResultArtifact(
            stageID: stageID,
            runID: runID
        ) else {
            return nil
        }
        return try JSONDecoder().decode(FlowStageResult.self, from: artifact.content)
    }

    private func loadPersistedStageResultArtifact(
        stageID: String,
        runID: String
    ) async throws -> (reference: ArtifactReference, content: Data)? {
        let ledger = try await ledgerCoordinator.load(runID: runID)
        let artifactID = try ArtifactID(rawValue: "\(stageID)-result")
        let identifierMatches = ledger.artifacts.filter { $0.id == artifactID }
        guard !identifierMatches.isEmpty else {
            return nil
        }
        let typedMatches = identifierMatches.filter {
            $0.locator.role == .output
                && $0.locator.kind == .other
                && $0.locator.format == .json
        }
        guard typedMatches.count == 1, let reference = typedMatches.first else {
            throw FlowExecutionError.invalidRunArtifactReference(
                artifactID: artifactID.rawValue,
                reason: "expected exactly one output JSON stage-result artifact, found \(typedMatches.count)"
            )
        }
        let content = try await infrastructure.loadArtifactContent(for: reference)
        return (reference, content)
    }

    private func validateStageResult(
        _ result: FlowStageResult,
        expectedStageID: String
    ) async throws {
        try stageResultValidator.validate(result, expectedStageID: expectedStageID)
        for artifact in result.artifacts {
            let integrity = await infrastructure.verifyArtifact(artifact)
            guard integrity.isVerified else {
                throw FlowExecutionError.artifactIntegrityFailure(
                    stageID: expectedStageID,
                    artifactID: artifact.id.rawValue,
                    artifactPath: artifact.locator.location.value,
                    issues: integrity.issues.map { $0.code.rawValue }
                )
            }
        }
    }

    private func blockedStageResult(
        stageID: String,
        diagnostics: [FlowDiagnostic],
        gateID: String? = nil
    ) -> FlowStageResult {
        let gates = gateID.map {
            [
                FlowGateResult(
                    gateID: $0,
                    status: .failed,
                    diagnostics: diagnostics
                ),
            ]
        } ?? []
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: diagnostics,
            gates: gates
        )
    }

    private func cancellationDiagnostics(
        _ cancellation: FlowRunCancellationRequest
    ) -> [FlowDiagnostic] {
        [
            FlowDiagnostic(
                severity: .warning,
                code: "RUN_CANCELLATION_REQUESTED",
                message: "Run cancellation was requested by \(cancellation.requestedBy): \(cancellation.reason)"
            ),
        ]
    }

    private func failedStageResult(
        stageID: String,
        code: String,
        message: String
    ) -> FlowStageResult {
        FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [
                FlowDiagnostic(
                    severity: .error,
                    code: code,
                    message: message
                ),
            ]
        )
    }

    private func diagnosticMessage(for error: any Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private func finalizeSetupFailure(
        request: FlowOperationRequest,
        runStartedAt: Date,
        preparedArtifacts: [ArtifactReference],
        error: any Error
    ) async throws {
        if !preparedArtifacts.isEmpty {
            _ = try await ledgerCoordinator.register(
                runID: request.runID,
                artifacts: preparedArtifacts
            )
        }
        let ledger = try await ledgerCoordinator.load(runID: request.runID)
        try await validateFailureProjectionArtifacts(ledger.artifacts)
        let stageID = "flow-setup"
        let failure = failedStageResult(
            stageID: stageID,
            code: "FLOW_RUN_SETUP_FAILED",
            message: diagnosticMessage(for: error)
        )
        let toolchain = FlowToolchainManifest(
            runID: request.runID,
            profile: request.toolchainProfile,
            stages: [
                FlowToolchainStageRecord(
                    stageID: stageID,
                    executorToolID: producer.identifier
                ),
            ]
        )
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: ledger.artifacts.filter { $0.locator.role == .input },
            startedAt: runStartedAt,
            completedAt: Date()
        )
        _ = try await ledgerCoordinator.finalizeFailure(
            runID: request.runID,
            stages: [failure],
            toolchain: toolchain,
            provenance: provenance
        )
    }

    private func finalizeExecutionFailure(
        request: FlowOperationRequest,
        runStartedAt: Date,
        activeStageID: String?,
        completedStages: [FlowStageResult],
        toolchainRecords: [FlowToolchainStageRecord],
        error: any Error
    ) async throws {
        let ledger = try await ledgerCoordinator.load(runID: request.runID)
        guard !ledger.runManifest.status.isTerminal else {
            return
        }
        try await validateFailureProjectionArtifacts(ledger.artifacts)
        let completedStageIDs = Set(completedStages.map(\.stageID))
        let failureStageID: String
        if let activeStageID, !completedStageIDs.contains(activeStageID) {
            failureStageID = activeStageID
        } else {
            failureStageID = "flow-execution"
        }
        let failure = failedStageResult(
            stageID: failureStageID,
            code: "FLOW_RUN_EXECUTION_FAILED",
            message: diagnosticMessage(for: error)
        )
        var stages = completedStages.filter { $0.stageID != failureStageID }
        stages.append(failure)
        var records = toolchainRecords.filter { $0.stageID != failureStageID }
        records.append(FlowToolchainStageRecord(
            stageID: failureStageID,
            executorToolID: producer.identifier
        ))
        let toolchain = FlowToolchainManifest(
            runID: request.runID,
            profile: request.toolchainProfile,
            stages: records
        )
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: ledger.artifacts.filter { $0.locator.role == .input },
            startedAt: runStartedAt,
            completedAt: Date()
        )
        _ = try await ledgerCoordinator.finalizeFailure(
            runID: request.runID,
            stages: stages,
            toolchain: toolchain,
            provenance: provenance
        )
    }

    private func validateFailureProjectionArtifacts(
        _ artifacts: [ArtifactReference]
    ) async throws {
        for artifact in artifacts {
            let integrity = await infrastructure.verifyArtifact(artifact)
            guard integrity.isVerified else {
                throw FlowExecutionError.runArtifactIntegrityFailure(
                    artifactID: artifact.id.rawValue,
                    issues: integrity.issues.map { $0.code.rawValue }
                )
            }
        }
    }

    private func persistRunResult(
        _ result: FlowRunResult,
        workspaceID: FlowWorkspaceID,
        toolchainProfile: FlowToolchainProfileRecord?,
        toolchainRecords: [FlowToolchainStageRecord]
    ) async throws {
        let progressArtifacts = try await progressStore.runLevelArtifacts(
            runID: result.runID,
        )
        var stageResultArtifacts: [ArtifactReference] = []
        for stage in result.stages {
            guard let persisted = try await loadPersistedStageResultArtifact(
                stageID: stage.stageID,
                runID: result.runID
            ) else {
                throw FlowExecutionError.missingArtifact(
                    "stage result \(stage.stageID) for run \(result.runID)"
                )
            }
            let retained = try JSONDecoder().decode(
                FlowStageResult.self,
                from: persisted.content
            )
            guard retained == stage else {
                throw FlowExecutionError.invalidRunArtifactReference(
                    artifactID: persisted.reference.id.rawValue,
                    reason: "retained stage result does not match the in-memory terminal projection"
                )
            }
            stageResultArtifacts.append(persisted.reference)
        }
        let toolchainReference = try await persistToolchainManifest(
            runID: result.runID,
            profile: toolchainProfile,
            records: toolchainRecords,
            workspaceID: workspaceID
        )
        let runLevelArtifacts = try await ledgerCoordinator.load(
            runID: result.runID
        ).artifacts
        let reportedStageArtifacts = result.stages
            .flatMap(\.artifacts)
            .map { $0 }
        var retainedStageArtifacts: [ArtifactReference] = []
        for artifact in reportedStageArtifacts {
            let integrity = await infrastructure.verifyArtifact(artifact)
            guard integrity.isVerified else {
                throw FlowExecutionError.artifactIntegrityFailure(
                    stageID: result.stages.first { $0.artifacts.contains(artifact) }?.stageID ?? "unknown",
                    artifactID: artifact.id.rawValue,
                    artifactPath: artifact.locator.location.value,
                    issues: integrity.issues.map { $0.code.rawValue }
                )
            }
            retainedStageArtifacts.append(artifact)
        }
        let artifacts = try mergedArtifactReferences(
            runLevelArtifacts
                + retainedStageArtifacts
                + stageResultArtifacts
                + progressArtifacts
                + [toolchainReference]
        )
        let toolchain = FlowToolchainManifest(
            runID: result.runID,
            profile: toolchainProfile,
            stages: toolchainRecords
        )
        let evidence = EvidenceManifest(
            provenance: result.evidence.provenance,
            artifacts: artifacts
        )
        _ = try await ledgerCoordinator.finalize(
            runID: result.runID,
            status: result.status,
            stages: result.stages,
            toolchain: toolchain,
            evidence: evidence,
            artifacts: artifacts
        )
    }

    private func persistRunPlan(
        request: FlowOperationRequest,
        workspaceID: FlowWorkspaceID
    ) async throws -> ArtifactReference {
        let plan = FlowRunPlan(
            runID: request.runID,
            intent: request.intent,
            toolchainProfile: request.toolchainProfile,
            stages: request.stages
        )
        let path = "runs/\(request.runID)/plan.json"
        if request.allowExistingRun,
           let existingPlan: FlowRunPlan = try await loadJSONArtifact(
               FlowRunPlan.self,
               path: path,
               role: .input,
               kind: .other,
               format: .json,
               workspaceID: workspaceID
           ) {
            guard existingPlan == plan else {
                throw FlowExecutionError.existingRunPlanMismatch(request.runID)
            }
        }
        return try await persistJSONArtifact(
            plan,
            path: path,
            id: "run-plan",
            role: .input,
            kind: .other,
            format: .json,
            runID: request.runID,
            workspaceID: workspaceID,
            mode: .immutable
        )
    }

    private func retainedRunPlanReference(
        for request: FlowOperationRequest
    ) async throws -> ArtifactReference {
        let ledger = try await ledgerCoordinator.load(runID: request.runID)
        let candidates = ledger.artifacts.filter {
            $0.id.rawValue == "run-plan"
                && $0.locator.role == .input
                && $0.locator.kind == .other
                && $0.locator.format == .json
        }
        guard candidates.count == 1, let reference = candidates.first else {
            throw FlowExecutionError.missingArtifact(
                "canonical run plan for run \(request.runID)"
            )
        }
        let integrity = await infrastructure.verifyArtifact(reference)
        guard integrity.isVerified else {
            throw FlowExecutionError.runArtifactIntegrityFailure(
                artifactID: reference.id.rawValue,
                issues: integrity.issues.map { $0.code.rawValue }
            )
        }
        let retainedPlan: FlowRunPlan
        do {
            retainedPlan = try JSONDecoder().decode(
                FlowRunPlan.self,
                from: await infrastructure.loadArtifactContent(for: reference)
            )
        } catch {
            throw FlowExecutionError.invalidRunArtifactReference(
                artifactID: reference.id.rawValue,
                reason: "canonical run plan cannot be decoded: \(error.localizedDescription)"
            )
        }
        let expectedPlan = FlowRunPlan(
            runID: request.runID,
            intent: request.intent,
            toolchainProfile: request.toolchainProfile,
            stages: request.stages
        )
        guard retainedPlan == expectedPlan else {
            throw FlowExecutionError.existingRunPlanMismatch(request.runID)
        }
        return reference
    }

    private func persistToolchainManifest(
        runID: String,
        profile: FlowToolchainProfileRecord?,
        records: [FlowToolchainStageRecord],
        workspaceID: FlowWorkspaceID
    ) async throws -> ArtifactReference {
        let manifest = FlowToolchainManifest(runID: runID, profile: profile, stages: records)
        return try await persistJSONArtifact(
            manifest,
            path: "runs/\(runID)/toolchain.json",
            id: "toolchain-manifest",
            role: .output,
            kind: .other,
            format: .json,
            runID: runID,
            workspaceID: workspaceID,
            mode: .replaceable
        )
    }

    private func persistJSONArtifact<Value: Encodable>(
        _ value: Value,
        path: String,
        id: String?,
        role: ArtifactRole,
        kind: ArtifactKind,
        format: ArtifactFormat,
        runID: String,
        workspaceID: FlowWorkspaceID,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference {
        let content = try encodedPackageJSON(value)
        let artifactID = try id.map(ArtifactID.init(rawValue:))
        return try await infrastructure.persistRunControlArtifact(
            content: content,
            id: artifactID,
            locator: try artifactLocator(
                path: path,
                role: role,
                kind: kind,
                format: format
            ),
            runID: runID,
            mode: mode
        )
    }

    private func loadJSONArtifact<Value: Decodable>(
        _ type: Value.Type,
        path: String,
        role: ArtifactRole,
        kind: ArtifactKind,
        format: ArtifactFormat,
        workspaceID: FlowWorkspaceID
    ) async throws -> Value? {
        let locator = try artifactLocator(
            path: path,
            role: role,
            kind: kind,
            format: format
        )
        guard let content = try await infrastructure.loadArtifactContent(
            at: locator
        ) else { return nil }
        return try JSONDecoder().decode(type, from: content)
    }

    private func artifactLocator(
        path: String,
        role: ArtifactRole,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactLocator {
        ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: role,
            kind: kind,
            format: format
        )
    }

    private func xcircuiteStatus(_ status: FlowRunStatus) -> FlowRunStatus {
        switch status {
        case .created:
            .created
        case .running:
            .running
        case .succeeded:
            .succeeded
        case .failed:
            .failed
        case .blocked:
            .blocked
        case .cancelled:
            .cancelled
        case .partial:
            .partial
        }
    }
}

private struct FlowStageExecutionOutcome: Sendable {
    var result: FlowStageResult
    var runStatusOverride: FlowRunStatus?

    init(
        result: FlowStageResult,
        runStatusOverride: FlowRunStatus? = nil
    ) {
        self.result = result
        self.runStatusOverride = runStatusOverride
    }
}

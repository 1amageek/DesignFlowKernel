import Foundation
import CircuiteFoundation
import ToolQualification

public struct DefaultFlowOrchestrator: Sendable {
    private let infrastructure: any FlowRunInfrastructure
    private let ledgerCoordinator: FlowRunLedgerCoordinator
    private let evaluator: ToolTrustEvaluator
    private let progressStore: FlowRunProgressStore

    public init(
        infrastructure: any FlowRunInfrastructure,
        ledgerPersistence: any FlowRunLedgerPersisting,
        evaluator: ToolTrustEvaluator = ToolTrustEvaluator(),
        progressStore: FlowRunProgressStore
    ) {
        self.infrastructure = infrastructure
        self.ledgerCoordinator = FlowRunLedgerCoordinator(persistence: ledgerPersistence)
        self.evaluator = evaluator
        self.progressStore = progressStore
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
        executors: [any FlowStageExecutor]
    ) async throws -> FlowRunResult {
        try validate(request: request)
        let executorsByStageID = try indexExecutors(executors)
        try validateExecutorCoverage(request: request, executorsByStageID: executorsByStageID)

        let runDirectory = try await infrastructure.prepareRunWorkspace(
            runID: request.runID,
            requireNew: !request.allowExistingRunDirectory
        )
        let previousRunArtifacts: [ArtifactReference]
        if request.allowExistingRunDirectory {
            previousRunArtifacts = try await ledgerCoordinator.load(runID: request.runID).artifacts
        } else {
            previousRunArtifacts = []
            let now = Date()
            let manifest = try FlowRunManifest(
                runID: request.runID,
                status: .created,
                actor: request.actor,
                intent: request.intent,
                createdAt: now,
                updatedAt: now
            )
            try await ledgerCoordinator.save(
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
        let planReference = try await persistRunPlan(
            request: request,
            projectRoot: request.projectRoot
        )
        _ = try await ledgerCoordinator.transition(
            runID: request.runID,
            to: .running,
            registering: [planReference]
        )
        try await progressStore.appendEvent(
            runID: request.runID,
            kind: .runStarted,
            runStatus: .running,
            message: "Run \(request.runID) started."
        )

        let context = FlowExecutionContext(
            projectRoot: request.projectRoot,
            runID: request.runID,
            runDirectory: runDirectory,
            infrastructure: infrastructure,
            toolRegistry: toolRegistry,
            healthResults: healthResults
        )
        var stageResults: [FlowStageResult] = []
        var toolchainRecords: [FlowToolchainStageRecord] = []

        for stage in request.stages {
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
                    projectRoot: request.projectRoot
                )
                stageResults.append(blocked)
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .cancellationObserved,
                    stageID: stage.stageID,
                    stageStatus: .blocked,
                    runStatus: .cancelled,
                    message: "Run cancellation observed before stage \(stage.stageID)."
                )
                let result = FlowRunResult(
                    runID: request.runID,
                    status: .cancelled,
                    stages: stageResults
                )
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .runFinished,
                    runStatus: .cancelled,
                    message: "Run \(request.runID) cancelled."
                )
                try await persistRunResult(
                    result,
                    projectRoot: request.projectRoot,
                    toolchainProfile: request.toolchainProfile,
                    toolchainRecords: toolchainRecords,
                    runLevelArtifacts: previousRunArtifacts + [planReference]
                )
                return result
            }

            if request.allowExistingRunDirectory,
               !stage.requiresApproval,
               let persisted = try await reusableStageResult(
                   for: stage,
                   runID: request.runID,
                   projectRoot: request.projectRoot
               ) {
                stageResults.append(persisted)
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
                        projectRoot: request.projectRoot
                    )
                    stageResults.append(result)
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
                        projectRoot: request.projectRoot
                    )
                    stageResults.append(result)
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .stageBlocked,
                        stageID: stage.stageID,
                        stageStatus: result.status,
                        runStatus: .blocked,
                        message: "Stage \(stage.stageID) blocked because its approval binding is stale."
                    )
                    let runResult = FlowRunResult(
                        runID: request.runID,
                        status: .blocked,
                        stages: stageResults
                    )
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .runFinished,
                        runStatus: .blocked,
                        message: "Run \(request.runID) blocked."
                    )
                    try await persistRunResult(
                        runResult,
                        projectRoot: request.projectRoot,
                        toolchainProfile: request.toolchainProfile,
                        toolchainRecords: toolchainRecords,
                        runLevelArtifacts: previousRunArtifacts + [planReference]
                    )
                    return runResult
                case .rejected(let result):
                    try await persistStageResult(
                        result,
                        runID: request.runID,
                        projectRoot: request.projectRoot
                    )
                    stageResults.append(result)
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: progressKind(for: result.status),
                        stageID: stage.stageID,
                        stageStatus: result.status,
                        runStatus: .failed,
                        message: "Stage \(stage.stageID) failed because its approval was rejected."
                    )
                    let runResult = FlowRunResult(
                        runID: request.runID,
                        status: .failed,
                        stages: stageResults
                    )
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .runFinished,
                        runStatus: .failed,
                        message: "Run \(request.runID) failed."
                    )
                    try await persistRunResult(
                        runResult,
                        projectRoot: request.projectRoot,
                        toolchainProfile: request.toolchainProfile,
                        toolchainRecords: toolchainRecords,
                        runLevelArtifacts: previousRunArtifacts + [planReference]
                    )
                    return runResult
                }
            }

            guard let executor = executorsByStageID[stage.stageID] else {
                throw FlowExecutionError.missingExecutor(stage.stageID)
            }
            var preExecutionGates: [FlowGateResult] = []
            var toolchainRecord = FlowToolchainStageRecord(
                stageID: stage.stageID,
                executorToolID: executor.toolID,
                requiredTool: stage.requiredTool
            )

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
                        projectRoot: request.projectRoot
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
                    let result = FlowRunResult(
                        runID: request.runID,
                        status: .blocked,
                        stages: stageResults
                    )
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .runFinished,
                        runStatus: .blocked,
                        message: "Run \(request.runID) blocked."
                    )
                    try await persistRunResult(
                        result,
                        projectRoot: request.projectRoot,
                        toolchainProfile: request.toolchainProfile,
                        toolchainRecords: toolchainRecords,
                        runLevelArtifacts: previousRunArtifacts + [planReference]
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
                        projectRoot: request.projectRoot
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
                    let result = FlowRunResult(
                        runID: request.runID,
                        status: .blocked,
                        stages: stageResults
                    )
                    try await progressStore.appendEvent(
                        runID: request.runID,
                        kind: .runFinished,
                        runStatus: .blocked,
                        message: "Run \(request.runID) blocked."
                    )
                    try await persistRunResult(
                        result,
                        projectRoot: request.projectRoot,
                        toolchainProfile: request.toolchainProfile,
                        toolchainRecords: toolchainRecords,
                        runLevelArtifacts: previousRunArtifacts + [planReference]
                    )
                    return result
                }

                preExecutionGates.append(toolTrustGate(
                    selectedTool: selectedTool.descriptor,
                    decision: selectedTool.decision
                ))
            }
            toolchainRecords.append(toolchainRecord)

            let stageOutcome = try await executeStageWithRetry(
                stage: stage,
                executor: executor,
                context: context,
                request: request,
                runDirectory: runDirectory,
                planReference: planReference,
                preExecutionGates: preExecutionGates
            )
            let result = stageOutcome.result
            try await persistStageResult(
                result,
                runID: request.runID,
                projectRoot: request.projectRoot
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
                let runResult = FlowRunResult(
                    runID: request.runID,
                    status: .cancelled,
                    stages: stageResults
                )
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .runFinished,
                    runStatus: .cancelled,
                    message: "Run \(request.runID) cancelled."
                )
                try await persistRunResult(
                    runResult,
                    projectRoot: request.projectRoot,
                    toolchainProfile: request.toolchainProfile,
                    toolchainRecords: toolchainRecords,
                    runLevelArtifacts: previousRunArtifacts + [planReference]
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
                let runResult = FlowRunResult(
                    runID: request.runID,
                    status: runStatus,
                    stages: stageResults
                )
                try await progressStore.appendEvent(
                    runID: request.runID,
                    kind: .runFinished,
                    runStatus: runStatus,
                    message: "Run \(request.runID) finished with status \(runStatus.rawValue)."
                )
                try await persistRunResult(
                    runResult,
                    projectRoot: request.projectRoot,
                    toolchainProfile: request.toolchainProfile,
                    toolchainRecords: toolchainRecords,
                    runLevelArtifacts: previousRunArtifacts + [planReference]
                )
                return runResult
            }
        }

        let runResult = FlowRunResult(
            runID: request.runID,
            status: aggregateStatus(stageResults),
            stages: stageResults
        )
        try await progressStore.appendEvent(
            runID: request.runID,
            kind: .runFinished,
            runStatus: runResult.status,
            message: "Run \(request.runID) finished with status \(runResult.status.rawValue)."
        )
        try await persistRunResult(
            runResult,
            projectRoot: request.projectRoot,
            toolchainProfile: request.toolchainProfile,
            toolchainRecords: toolchainRecords,
            runLevelArtifacts: previousRunArtifacts + [planReference]
        )
        return runResult
    }

    private func executeStageWithRetry(
        stage: FlowStageDefinition,
        executor: any FlowStageExecutor,
        context: FlowExecutionContext,
        request: FlowOperationRequest,
        runDirectory: URL,
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
                request: request,
                runDirectory: runDirectory
            )
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
            let resultPath = "runs/\(request.runID)/stages/\(stage.stageID)/result.json"
            guard let reviewedResult: FlowStageResult = try await loadJSONArtifact(
                FlowStageResult.self,
                path: resultPath,
                role: .output,
                kind: .other,
                format: .json,
                projectRoot: request.projectRoot
            ) else {
                let diagnostic = FlowDiagnostic(
                    severity: .error,
                    code: "APPROVAL_REVIEW_INPUT_MISSING",
                    message: "Approved stage \(stage.stageID) is missing its reviewed result."
                )
                return .blocked(approvalBindingBlockedStageResult(stageID: stage.stageID, diagnostic: diagnostic))
            }
            if isApprovalApplied(to: reviewedResult) {
                let approvalInputPath = "runs/\(request.runID)/stages/\(stage.stageID)/approval-input.json"
                let approvalInputLocator = try artifactLocator(
                    path: approvalInputPath,
                    role: .input,
                    kind: .report,
                    format: .json
                )
                guard let approvalInputContent = try await infrastructure.loadArtifactContent(
                    at: approvalInputLocator
                ) else {
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
                    let diagnostics = try validator.validateApproval(
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
            _ = try await persistJSONArtifact(
                reviewedResult,
                path: "runs/\(request.runID)/stages/\(stage.stageID)/approval-input.json",
                id: "approval-review-\(stage.stageID.replacingOccurrences(of: ".", with: "-"))",
                role: .input,
                kind: .report,
                format: .json,
                runID: request.runID,
                projectRoot: request.projectRoot,
                mode: .immutable
            )
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
        updated.gates.append(FlowGateResult(gateID: "approval", status: .passed, diagnostics: [diagnostic]))
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
            updated.gates.append(FlowGateResult(
                gateID: "approval",
                status: .passed,
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
        request: FlowOperationRequest,
        runDirectory: URL
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
            projectRoot: request.projectRoot
        )
        updated.artifacts = mergedFoundationArtifacts(updated.artifacts + [reference])
        return updated
    }

    private func persistStageAttemptRecords(
        _ attempts: [FlowStageAttemptRecord],
        stageID: String,
        runID: String,
        projectRoot: URL
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
            projectRoot: projectRoot,
            mode: .replaceable
        )
    }

    private func diagnosticCodes(from result: FlowStageResult) -> [String] {
        Array(Set((result.diagnostics + result.gates.flatMap(\.diagnostics)).map(\.code))).sorted()
    }

    private func persistStageResult(
        _ result: FlowStageResult,
        runID: String,
        projectRoot: URL
    ) async throws {
        _ = try await persistJSONArtifact(
            result,
            path: "runs/\(runID)/stages/\(result.stageID)/result.json",
            id: "\(result.stageID)-result",
            role: .output,
            kind: .other,
            format: .json,
            runID: runID,
            projectRoot: projectRoot,
            mode: .replaceable
        )
    }

    private func reusableStageResult(
        for stage: FlowStageDefinition,
        runID: String,
        projectRoot: URL
    ) async throws -> FlowStageResult? {
        guard let result: FlowStageResult = try await loadJSONArtifact(
            FlowStageResult.self,
            path: "runs/\(runID)/stages/\(stage.stageID)/result.json",
            role: .output,
            kind: .other,
            format: .json,
            projectRoot: projectRoot
        ) else { return nil }
        guard result.stageID == stage.stageID, result.status == .succeeded else {
            return nil
        }
        return result
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

    private func persistRunResult(
        _ result: FlowRunResult,
        projectRoot: URL,
        toolchainProfile: FlowToolchainProfileRecord?,
        toolchainRecords: [FlowToolchainStageRecord],
        runLevelArtifacts: [ArtifactReference]
    ) async throws {
        let progressArtifacts = try await progressStore.runLevelArtifacts(
            runID: result.runID,
        )
        var stageResultArtifacts: [ArtifactReference] = []
        for stage in result.stages {
            let locator = try artifactLocator(
                path: "runs/\(result.runID)/stages/\(stage.stageID)/result.json",
                role: .output,
                kind: .other,
                format: .json
            )
            guard let content = try await infrastructure.loadArtifactContent(
                at: locator
            ) else {
                throw FlowExecutionError.missingArtifact(
                    "runs/\(result.runID)/stages/\(stage.stageID)/result.json"
                )
            }
            let reference = try await infrastructure.persistArtifact(
                content: content,
                id: ArtifactID(rawValue: "\(stage.stageID)-result"),
                locator: locator,
                runID: result.runID,
                mode: .replaceable
            )
            stageResultArtifacts.append(reference)
        }
        let toolchainReference = try await persistToolchainManifest(
            runID: result.runID,
            profile: toolchainProfile,
            records: toolchainRecords,
            projectRoot: projectRoot
        )
        let reportedStageArtifacts = result.stages
            .flatMap(\.artifacts)
            .map { $0 }
        var retainedStageArtifacts: [ArtifactReference] = []
        for artifact in reportedStageArtifacts {
            let integrity = await infrastructure.verifyArtifact(artifact)
            if integrity.isVerified {
                retainedStageArtifacts.append(artifact)
            }
        }
        let artifacts = mergedFoundationArtifacts(
            runLevelArtifacts
                + retainedStageArtifacts
                + stageResultArtifacts
                + progressArtifacts
                + [toolchainReference]
        )
        _ = try await ledgerCoordinator.update(
            runID: result.runID,
        ) { ledger in
            ledger.stages = result.stages
            ledger.toolchain = FlowToolchainManifest(
                runID: result.runID,
                profile: toolchainProfile,
                stages: toolchainRecords
            )
            ledger.artifacts = artifacts
            ledger.runManifest.artifacts = artifacts
        }
        _ = try await ledgerCoordinator.transition(
            runID: result.runID,
            to: result.status,
            registering: artifacts
        )
    }

    private func persistRunPlan(
        request: FlowOperationRequest,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        let plan = FlowRunPlan(
            runID: request.runID,
            intent: request.intent,
            toolchainProfile: request.toolchainProfile,
            stages: request.stages
        )
        let path = "runs/\(request.runID)/plan.json"
        if request.allowExistingRunDirectory,
           let existingPlan: FlowRunPlan = try await loadJSONArtifact(
               FlowRunPlan.self,
               path: path,
               role: .input,
               kind: .other,
               format: .json,
               projectRoot: projectRoot
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
            projectRoot: projectRoot,
            mode: .immutable
        )
    }

    private func mergedArtifacts(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        var byPath: [String: ArtifactReference] = [:]
        for artifact in artifacts {
            byPath[artifact.path] = artifact
        }
        return byPath.values.sorted { $0.path < $1.path }
    }

    private func mergedFoundationArtifacts(
        _ artifacts: [ArtifactReference]
    ) -> [ArtifactReference] {
        var byIdentity: [String: ArtifactReference] = [:]
        for artifact in artifacts {
            byIdentity[artifact.id.rawValue] = artifact
        }
        return byIdentity.values.sorted { $0.path < $1.path }
    }

    private func persistToolchainManifest(
        runID: String,
        profile: FlowToolchainProfileRecord?,
        records: [FlowToolchainStageRecord],
        projectRoot: URL
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
            projectRoot: projectRoot,
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
        projectRoot: URL,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference {
        let content = try encodedPackageJSON(value)
        let artifactID = try id.map(ArtifactID.init(rawValue:))
        return try await infrastructure.persistArtifact(
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
        projectRoot: URL
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

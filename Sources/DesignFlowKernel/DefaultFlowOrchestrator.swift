import Foundation
import ToolQualification
import XcircuitePackage

public struct DefaultFlowOrchestrator: Sendable {
    private let packageStore: XcircuitePackageStore
    private let evaluator: ToolTrustEvaluator
    private let progressStore: FlowRunProgressStore

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        evaluator: ToolTrustEvaluator = ToolTrustEvaluator(),
        progressStore: FlowRunProgressStore = FlowRunProgressStore()
    ) {
        self.packageStore = packageStore
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

        try packageStore.createPackage(at: request.projectRoot)
        try validateRunDirectoryAvailability(request)
        let previousRunArtifacts: [XcircuiteFileReference]
        if request.allowExistingRunDirectory {
            previousRunArtifacts = try existingRunArtifacts(
                runID: request.runID,
                projectRoot: request.projectRoot
            )
        } else {
            previousRunArtifacts = []
        }
        let runDirectory = try runDirectory(for: request)
        let planReference = try persistRunPlan(
            request: request,
            runDirectory: runDirectory
        )
        try progressStore.appendEvent(
            runID: request.runID,
            projectRoot: request.projectRoot,
            kind: .runStarted,
            runStatus: .running,
            message: "Run \(request.runID) started."
        )

        let context = FlowExecutionContext(
            projectRoot: request.projectRoot,
            runID: request.runID,
            runDirectory: runDirectory,
            packageStore: packageStore,
            toolRegistry: toolRegistry,
            healthResults: healthResults
        )
        var stageResults: [FlowStageResult] = []
        var toolchainRecords: [FlowToolchainStageRecord] = []

        for stage in request.stages {
            if let cancellation = try progressStore.loadCancellationRequest(
                runID: request.runID,
                projectRoot: request.projectRoot
            ) {
                let diagnostics = cancellationDiagnostics(cancellation)
                let blocked = blockedStageResult(
                    stageID: stage.stageID,
                    diagnostics: diagnostics,
                    gateID: "cancellation"
                )
                try persistStageResult(
                    blocked,
                    projectRoot: request.projectRoot,
                    runDirectory: runDirectory
                )
                stageResults.append(blocked)
                try progressStore.appendEvent(
                    runID: request.runID,
                    projectRoot: request.projectRoot,
                    kind: .cancellationObserved,
                    stageID: stage.stageID,
                    stageStatus: .blocked,
                    runStatus: .cancelled,
                    message: "Run cancellation observed before stage \(stage.stageID)."
                )
                let result = FlowRunResult(
                    runID: request.runID,
                    status: .cancelled,
                    runDirectory: runDirectory,
                    stages: stageResults
                )
                try progressStore.appendEvent(
                    runID: request.runID,
                    projectRoot: request.projectRoot,
                    kind: .runFinished,
                    runStatus: .cancelled,
                    message: "Run \(request.runID) cancelled."
                )
                try persistRunResult(
                    result,
                    projectRoot: request.projectRoot,
                    runDirectory: runDirectory,
                    toolchainProfile: request.toolchainProfile,
                    toolchainRecords: toolchainRecords,
                    runLevelArtifacts: previousRunArtifacts + [planReference]
                )
                return result
            }

            if stage.requiresApproval {
                switch try persistedApprovalResolution(
                    for: stage,
                    request: request,
                    runDirectory: runDirectory,
                    planReference: planReference
                ) {
                case .none:
                    break
                case .approved(let result):
                    try persistStageResult(
                        result,
                        projectRoot: request.projectRoot,
                        runDirectory: runDirectory
                    )
                    stageResults.append(result)
                    try progressStore.appendEvent(
                        runID: request.runID,
                        projectRoot: request.projectRoot,
                        kind: progressKind(for: result.status),
                        stageID: stage.stageID,
                        stageStatus: result.status,
                        runStatus: aggregateStatus(stageResults),
                        message: "Stage \(stage.stageID) resumed from a content-bound approval."
                    )
                    continue
                case .blocked(let result):
                    try persistStageResult(
                        result,
                        projectRoot: request.projectRoot,
                        runDirectory: runDirectory
                    )
                    stageResults.append(result)
                    try progressStore.appendEvent(
                        runID: request.runID,
                        projectRoot: request.projectRoot,
                        kind: .stageBlocked,
                        stageID: stage.stageID,
                        stageStatus: result.status,
                        runStatus: .blocked,
                        message: "Stage \(stage.stageID) blocked because its approval binding is stale."
                    )
                    let runResult = FlowRunResult(
                        runID: request.runID,
                        status: .blocked,
                        runDirectory: runDirectory,
                        stages: stageResults
                    )
                    try progressStore.appendEvent(
                        runID: request.runID,
                        projectRoot: request.projectRoot,
                        kind: .runFinished,
                        runStatus: .blocked,
                        message: "Run \(request.runID) blocked."
                    )
                    try persistRunResult(
                        runResult,
                        projectRoot: request.projectRoot,
                        runDirectory: runDirectory,
                        toolchainProfile: request.toolchainProfile,
                        toolchainRecords: toolchainRecords,
                        runLevelArtifacts: previousRunArtifacts + [planReference]
                    )
                    return runResult
                case .rejected(let result):
                    try persistStageResult(
                        result,
                        projectRoot: request.projectRoot,
                        runDirectory: runDirectory
                    )
                    stageResults.append(result)
                    try progressStore.appendEvent(
                        runID: request.runID,
                        projectRoot: request.projectRoot,
                        kind: progressKind(for: result.status),
                        stageID: stage.stageID,
                        stageStatus: result.status,
                        runStatus: .failed,
                        message: "Stage \(stage.stageID) failed because its approval was rejected."
                    )
                    let runResult = FlowRunResult(
                        runID: request.runID,
                        status: .failed,
                        runDirectory: runDirectory,
                        stages: stageResults
                    )
                    try progressStore.appendEvent(
                        runID: request.runID,
                        projectRoot: request.projectRoot,
                        kind: .runFinished,
                        runStatus: .failed,
                        message: "Run \(request.runID) failed."
                    )
                    try persistRunResult(
                        runResult,
                        projectRoot: request.projectRoot,
                        runDirectory: runDirectory,
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
                let evaluatedTools = evaluatedToolDecisions(
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
                    try persistStageResult(
                        blocked,
                        projectRoot: request.projectRoot,
                        runDirectory: runDirectory
                    )
                    stageResults.append(blocked)
                    try progressStore.appendEvent(
                        runID: request.runID,
                        projectRoot: request.projectRoot,
                        kind: .stageBlocked,
                        stageID: stage.stageID,
                        stageStatus: .blocked,
                        runStatus: .blocked,
                        message: "Stage \(stage.stageID) blocked before execution."
                    )
                    let result = FlowRunResult(
                        runID: request.runID,
                        status: .blocked,
                        runDirectory: runDirectory,
                        stages: stageResults
                    )
                    try progressStore.appendEvent(
                        runID: request.runID,
                        projectRoot: request.projectRoot,
                        kind: .runFinished,
                        runStatus: .blocked,
                        message: "Run \(request.runID) blocked."
                    )
                    try persistRunResult(
                        result,
                        projectRoot: request.projectRoot,
                        runDirectory: runDirectory,
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
                    try persistStageResult(
                        blocked,
                        projectRoot: request.projectRoot,
                        runDirectory: runDirectory
                    )
                    stageResults.append(blocked)
                    try progressStore.appendEvent(
                        runID: request.runID,
                        projectRoot: request.projectRoot,
                        kind: .stageBlocked,
                        stageID: stage.stageID,
                        stageStatus: .blocked,
                        runStatus: .blocked,
                        message: "Stage \(stage.stageID) blocked by executor/tool mismatch."
                    )
                    let result = FlowRunResult(
                        runID: request.runID,
                        status: .blocked,
                        runDirectory: runDirectory,
                        stages: stageResults
                    )
                    try progressStore.appendEvent(
                        runID: request.runID,
                        projectRoot: request.projectRoot,
                        kind: .runFinished,
                        runStatus: .blocked,
                        message: "Run \(request.runID) blocked."
                    )
                    try persistRunResult(
                        result,
                        projectRoot: request.projectRoot,
                        runDirectory: runDirectory,
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
            try persistStageResult(
                result,
                projectRoot: request.projectRoot,
                runDirectory: runDirectory
            )
            stageResults.append(result)

            if stageOutcome.runStatusOverride == .cancelled {
                try progressStore.appendEvent(
                    runID: request.runID,
                    projectRoot: request.projectRoot,
                    kind: .cancellationObserved,
                    stageID: stage.stageID,
                    stageStatus: .blocked,
                    runStatus: .cancelled,
                    message: "Run cancellation observed during stage \(stage.stageID)."
                )
                let runResult = FlowRunResult(
                    runID: request.runID,
                    status: .cancelled,
                    runDirectory: runDirectory,
                    stages: stageResults
                )
                try progressStore.appendEvent(
                    runID: request.runID,
                    projectRoot: request.projectRoot,
                    kind: .runFinished,
                    runStatus: .cancelled,
                    message: "Run \(request.runID) cancelled."
                )
                try persistRunResult(
                    runResult,
                    projectRoot: request.projectRoot,
                    runDirectory: runDirectory,
                    toolchainProfile: request.toolchainProfile,
                    toolchainRecords: toolchainRecords,
                    runLevelArtifacts: previousRunArtifacts + [planReference]
                )
                return runResult
            }
            try progressStore.appendEvent(
                runID: request.runID,
                projectRoot: request.projectRoot,
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
                    runDirectory: runDirectory,
                    stages: stageResults
                )
                try progressStore.appendEvent(
                    runID: request.runID,
                    projectRoot: request.projectRoot,
                    kind: .runFinished,
                    runStatus: runStatus,
                    message: "Run \(request.runID) finished with status \(runStatus.rawValue)."
                )
                try persistRunResult(
                    runResult,
                    projectRoot: request.projectRoot,
                    runDirectory: runDirectory,
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
            runDirectory: runDirectory,
            stages: stageResults
        )
        try progressStore.appendEvent(
            runID: request.runID,
            projectRoot: request.projectRoot,
            kind: .runFinished,
            runStatus: runResult.status,
            message: "Run \(request.runID) finished with status \(runResult.status.rawValue)."
        )
        try persistRunResult(
            runResult,
            projectRoot: request.projectRoot,
            runDirectory: runDirectory,
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
        planReference: XcircuiteFileReference,
        preExecutionGates: [FlowGateResult]
    ) async throws -> FlowStageExecutionOutcome {
        var attempts: [FlowStageAttemptRecord] = []
        var attemptIndex = 1
        let maxAttempts = stage.retryPolicy.maxAttempts

        while attemptIndex <= maxAttempts {
            let startedAt = Date()
            try progressStore.appendEvent(
                runID: request.runID,
                projectRoot: request.projectRoot,
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
                attemptResult = try applyApprovalGate(
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
                try progressStore.appendEvent(
                    runID: request.runID,
                    projectRoot: request.projectRoot,
                    kind: .stageRetryScheduled,
                    stageID: stage.stageID,
                    stageStatus: attemptResult.status,
                    runStatus: .running,
                    message: "Stage \(stage.stageID) retry scheduled after attempt \(attemptIndex)."
                )
                attemptIndex += 1
                continue
            }

            let finalResult = try attachAttemptRecordsIfNeeded(
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
    ) -> [(descriptor: ToolDescriptor, decision: ToolTrustDecision)] {
        toolRegistry.descriptors.values
            .map { descriptor in
                (
                    descriptor,
                    evaluator.evaluate(
                        descriptor: descriptor,
                        requirement: requirement,
                        health: healthResults[descriptor.toolID]
                    )
                )
            }
            .sorted { lhs, rhs in
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
        runDirectory: URL,
        planReference: XcircuiteFileReference
    ) throws -> PersistedApprovalResolution {
        guard let record = try packageStore.loadApproval(
            runID: request.runID,
            stageID: stage.stageID,
            inProjectAt: request.projectRoot
        ) else {
            return .none
        }

        switch record.verdict {
        case .rejected:
            return .rejected(rejectedStageResult(stageID: stage.stageID, record: record))
        case .approved:
            if let diagnostic = approvalBindingDiagnostic(
                record: record,
                planReference: planReference,
                runDirectory: runDirectory
            ) {
                return .blocked(approvalBindingBlockedStageResult(stageID: stage.stageID, diagnostic: diagnostic))
            }
            let resultURL = runDirectory
                .appending(path: "stages")
                .appending(path: stage.stageID)
                .appending(path: "result.json")
            let reviewedResult = try packageStore.readJSON(FlowStageResult.self, from: resultURL)
            guard reviewedResult.stageID == stage.stageID else {
                let diagnostic = FlowDiagnostic(
                    severity: .error,
                    code: "APPROVAL_BINDING_MISMATCH",
                    message: "Approval targets stage \(stage.stageID), but the reviewed result belongs to \(reviewedResult.stageID). Re-approval is required."
                )
                return .blocked(approvalBindingBlockedStageResult(stageID: stage.stageID, diagnostic: diagnostic))
            }
            return .approved(approvedStageResult(from: reviewedResult, record: record))
        }
    }

    private func approvalBindingDiagnostic(
        record: XcircuiteApprovalRecord,
        planReference: XcircuiteFileReference,
        runDirectory: URL
    ) -> FlowDiagnostic? {
        guard let planSHA256 = record.planSHA256,
              let planByteCount = record.planByteCount,
              let stageResultSHA256 = record.stageResultSHA256,
              let stageResultByteCount = record.stageResultByteCount else {
            return FlowDiagnostic(
                severity: .error,
                code: "APPROVAL_BINDING_MISSING",
                message: "Approval for \(record.stageID) does not record the reviewed plan and stage result hashes. Re-approval is required."
            )
        }
        guard planReference.sha256 == planSHA256,
              planReference.byteCount == planByteCount else {
            return FlowDiagnostic(
                severity: .error,
                code: "APPROVAL_BINDING_MISMATCH",
                message: "Approval for \(record.stageID) was recorded for a different plan.json. Re-approval is required."
            )
        }

        let resultURL = runDirectory
            .appending(path: "stages")
            .appending(path: record.stageID)
            .appending(path: "result.json")
        guard FileManager.default.fileExists(atPath: resultURL.path(percentEncoded: false)) else {
            return FlowDiagnostic(
                severity: .error,
                code: "APPROVAL_BINDING_MISMATCH",
                message: "Approval for \(record.stageID) references a stage result that is no longer present. Re-approval is required."
            )
        }

        do {
            let actualSHA256 = try XcircuiteHasher().sha256(fileAt: resultURL)
            let actualByteCount = try XcircuiteHasher().byteCount(fileAt: resultURL)
            guard actualSHA256 == stageResultSHA256,
                  actualByteCount == stageResultByteCount else {
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

    private func approvalBindingDiagnostic(
        record: XcircuiteApprovalRecord,
        planReference: XcircuiteFileReference,
        stageResult: FlowStageResult
    ) -> FlowDiagnostic? {
        guard let planSHA256 = record.planSHA256,
              let planByteCount = record.planByteCount,
              let stageResultSHA256 = record.stageResultSHA256,
              let stageResultByteCount = record.stageResultByteCount else {
            return FlowDiagnostic(
                severity: .error,
                code: "APPROVAL_BINDING_MISSING",
                message: "Approval for \(record.stageID) does not record the reviewed plan and stage result hashes. Re-approval is required."
            )
        }
        guard planReference.sha256 == planSHA256,
              planReference.byteCount == planByteCount else {
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
            let actualSHA256 = XcircuiteHasher().sha256(data: data)
            let actualByteCount = Int64(data.count)
            guard actualSHA256 == stageResultSHA256,
                  actualByteCount == stageResultByteCount else {
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

    private func approvedStageResult(
        from result: FlowStageResult,
        record: XcircuiteApprovalRecord
    ) -> FlowStageResult {
        var updated = result
        updated.status = .succeeded
        updated.gates.removeAll { $0.gateID == "approval" }
        updated.diagnostics.removeAll { approvalGateDiagnosticCodes.contains($0.code) }
        let diagnostic = approvedDiagnostic(record)
        updated.gates.append(FlowGateResult(gateID: "approval", status: .passed, diagnostics: [diagnostic]))
        updated.diagnostics.append(diagnostic)
        return updated
    }

    private func rejectedStageResult(
        stageID: String,
        record: XcircuiteApprovalRecord
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
            "STAGE_REJECTED",
        ]
    }

    private func approvedDiagnostic(_ record: XcircuiteApprovalRecord) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: .info,
            code: "STAGE_APPROVED",
            message: "Approved by \(record.reviewer)\(record.note.isEmpty ? "" : ": \(record.note)")."
        )
    }

    private func rejectedDiagnostic(_ record: XcircuiteApprovalRecord) -> FlowDiagnostic {
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
        planReference: XcircuiteFileReference
    ) throws -> FlowStageResult {
        var updated = result
        guard result.status == .succeeded else { return result }

        let record = try packageStore.loadApproval(
            runID: request.runID,
            stageID: result.stageID,
            inProjectAt: request.projectRoot
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
        case .approved:
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
            let diagnostic = approvedDiagnostic(record)
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
        let validator = XcircuiteIdentifierValidator()
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

    private func validateRunDirectoryAvailability(_ request: FlowOperationRequest) throws {
        guard !request.allowExistingRunDirectory else { return }
        let runDirectory = try XcircuitePackage(projectRoot: request.projectRoot)
            .runDirectoryURL(for: request.runID)
        guard !FileManager.default.fileExists(atPath: runDirectory.path(percentEncoded: false)) else {
            throw FlowExecutionError.duplicateRunID(request.runID)
        }
    }

    private func runDirectory(for request: FlowOperationRequest) throws -> URL {
        if request.allowExistingRunDirectory {
            return try packageStore.ensureRunDirectory(
                for: request.runID,
                inProjectAt: request.projectRoot
            )
        }
        return try packageStore.createRunDirectory(
            for: request.runID,
            inProjectAt: request.projectRoot
        )
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
        let validator = XcircuiteIdentifierValidator()
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
    ) throws -> FlowStageResult {
        var updated = result
        updated.attempts = attempts
        guard stage.retryPolicy.isEnabled || attempts.count > 1 else {
            return updated
        }

        let reference = try persistStageAttemptRecords(
            attempts,
            stageID: stage.stageID,
            runID: request.runID,
            projectRoot: request.projectRoot,
            runDirectory: runDirectory
        )
        updated.artifacts = mergedArtifacts(updated.artifacts + [reference])
        return updated
    }

    private func persistStageAttemptRecords(
        _ attempts: [FlowStageAttemptRecord],
        stageID: String,
        runID: String,
        projectRoot: URL,
        runDirectory: URL
    ) throws -> XcircuiteFileReference {
        let relativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/stages/\(stageID)/attempts.json"
        let attemptsURL = runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "attempts.json")
        try packageStore.ensureDirectory(at: attemptsURL.deletingLastPathComponent())
        try packageStore.writeJSON(attempts, to: attemptsURL, forProjectAt: projectRoot)
        return try packageStore.fileReference(
            forProjectRelativePath: relativePath,
            artifactID: "\(stageID)-attempts",
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
    }

    private func diagnosticCodes(from result: FlowStageResult) -> [String] {
        Array(Set((result.diagnostics + result.gates.flatMap(\.diagnostics)).map(\.code))).sorted()
    }

    private func persistStageResult(
        _ result: FlowStageResult,
        projectRoot: URL,
        runDirectory: URL
    ) throws {
        let stageDirectory = runDirectory.appending(path: "stages").appending(path: result.stageID)
        try packageStore.ensureDirectory(at: stageDirectory)
        try packageStore.writeJSON(
            result,
            to: stageDirectory.appending(path: "result.json"),
            forProjectAt: projectRoot
        )
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
        runDirectory: URL,
        toolchainProfile: FlowToolchainProfileRecord?,
        toolchainRecords: [FlowToolchainStageRecord],
        runLevelArtifacts: [XcircuiteFileReference]
    ) throws {
        let progressArtifacts = try progressStore.runLevelArtifacts(
            runID: result.runID,
            projectRoot: projectRoot
        )
        let stageResultArtifacts = try result.stages.map { stage in
            try packageStore.fileReference(
                forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(result.runID)/stages/\(stage.stageID)/result.json",
                artifactID: "\(stage.stageID)-result",
                kind: .other,
                format: .json,
                inProjectAt: projectRoot,
                producedByRunID: result.runID
            )
        }
        let toolchainReference = try persistToolchainManifest(
            runID: result.runID,
            profile: toolchainProfile,
            records: toolchainRecords,
            projectRoot: projectRoot,
            runDirectory: runDirectory
        )
        let artifacts = mergedArtifacts(
            runLevelArtifacts
                + result.stages.flatMap(\.artifacts)
                + stageResultArtifacts
                + progressArtifacts
                + [toolchainReference]
        )
        let runManifest = XcircuiteRunManifest(
            runID: result.runID,
            status: xcircuiteStatus(result.status),
            artifacts: artifacts
        )
        try packageStore.writeJSON(
            runManifest,
            to: runDirectory.appending(path: "manifest.json"),
            forProjectAt: projectRoot
        )
        let runManifestReference = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(result.runID)/manifest.json",
            artifactID: "run-manifest",
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: result.runID
        )
        try packageStore.upsertFileReference(runManifestReference, forProjectAt: projectRoot)
    }

    private func persistRunPlan(
        request: FlowOperationRequest,
        runDirectory: URL
    ) throws -> XcircuiteFileReference {
        let plan = FlowRunPlan(
            runID: request.runID,
            intent: request.intent,
            toolchainProfile: request.toolchainProfile,
            stages: request.stages
        )
        let planURL = runDirectory.appending(path: "plan.json")
        if request.allowExistingRunDirectory,
           FileManager.default.fileExists(atPath: planURL.path(percentEncoded: false)) {
            let existingPlan = try packageStore.readJSON(FlowRunPlan.self, from: planURL)
            guard existingPlan == plan else {
                throw FlowExecutionError.existingRunPlanMismatch(request.runID)
            }
            return try packageStore.fileReference(
                forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(request.runID)/plan.json",
                kind: .other,
                format: .json,
                inProjectAt: request.projectRoot,
                producedByRunID: request.runID
            )
        }
        try packageStore.writeJSON(plan, to: planURL, forProjectAt: request.projectRoot)
        return try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(request.runID)/plan.json",
            kind: .other,
            format: .json,
            inProjectAt: request.projectRoot,
            producedByRunID: request.runID
        )
    }

    private func existingRunArtifacts(
        runID: String,
        projectRoot: URL
    ) throws -> [XcircuiteFileReference] {
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let manifestURL = runDirectory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            return []
        }
        return try packageStore.readJSON(XcircuiteRunManifest.self, from: manifestURL).artifacts
    }

    private func mergedArtifacts(_ artifacts: [XcircuiteFileReference]) -> [XcircuiteFileReference] {
        var byPath: [String: XcircuiteFileReference] = [:]
        for artifact in artifacts {
            byPath[artifact.path] = artifact
        }
        return byPath.values.sorted { $0.path < $1.path }
    }

    private func persistToolchainManifest(
        runID: String,
        profile: FlowToolchainProfileRecord?,
        records: [FlowToolchainStageRecord],
        projectRoot: URL,
        runDirectory: URL
    ) throws -> XcircuiteFileReference {
        let toolchainURL = runDirectory.appending(path: "toolchain.json")
        let manifest = FlowToolchainManifest(runID: runID, profile: profile, stages: records)
        try packageStore.writeJSON(manifest, to: toolchainURL, forProjectAt: projectRoot)
        return try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/toolchain.json",
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
    }

    private func xcircuiteStatus(_ status: FlowRunStatus) -> XcircuiteRunStatus {
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

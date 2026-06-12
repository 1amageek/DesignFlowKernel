import Foundation
import ToolQualification
import XcircuitePackage

public struct DefaultFlowOrchestrator: Sendable {
    private let packageStore: XcircuitePackageStore
    private let evaluator: ToolTrustEvaluator

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        evaluator: ToolTrustEvaluator = ToolTrustEvaluator()
    ) {
        self.packageStore = packageStore
        self.evaluator = evaluator
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
        let runDirectory = try packageStore.createRunDirectory(
            for: request.runID,
            inProjectAt: request.projectRoot
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

        for stage in request.stages {
            let executor = executorsByStageID[stage.stageID]!

            if let requiredTool = stage.requiredTool {
                let selectedTool = toolRegistry.select(
                    requirement: requiredTool,
                    healthResults: healthResults,
                    evaluator: evaluator
                )
                guard let selectedTool else {
                    let blocked = blockedStageResult(
                        stageID: stage.stageID,
                        code: "NO_ELIGIBLE_TOOL",
                        message: "No registered tool satisfies the stage trust requirement."
                    )
                    try persistStageResult(
                        blocked,
                        projectRoot: request.projectRoot,
                        runDirectory: runDirectory
                    )
                    stageResults.append(blocked)
                    let result = FlowRunResult(
                        runID: request.runID,
                        status: .blocked,
                        runDirectory: runDirectory,
                        stages: stageResults
                    )
                    try persistRunResult(result, projectRoot: request.projectRoot, runDirectory: runDirectory)
                    return result
                }

                guard selectedTool.toolID == executor.toolID else {
                    let blocked = blockedStageResult(
                        stageID: stage.stageID,
                        code: "EXECUTOR_TOOL_MISMATCH",
                        message: "Selected tool \(selectedTool.toolID) does not match executor tool \(executor.toolID)."
                    )
                    try persistStageResult(
                        blocked,
                        projectRoot: request.projectRoot,
                        runDirectory: runDirectory
                    )
                    stageResults.append(blocked)
                    let result = FlowRunResult(
                        runID: request.runID,
                        status: .blocked,
                        runDirectory: runDirectory,
                        stages: stageResults
                    )
                    try persistRunResult(result, projectRoot: request.projectRoot, runDirectory: runDirectory)
                    return result
                }
            }

            var result: FlowStageResult
            do {
                result = try await executor.execute(stage: stage, context: context)
            } catch {
                let failed = failedStageResult(
                    stageID: stage.stageID,
                    code: "STAGE_EXECUTOR_FAILED",
                    message: diagnosticMessage(for: error)
                )
                try persistStageResult(
                    failed,
                    projectRoot: request.projectRoot,
                    runDirectory: runDirectory
                )
                stageResults.append(failed)
                let runResult = FlowRunResult(
                    runID: request.runID,
                    status: .failed,
                    runDirectory: runDirectory,
                    stages: stageResults
                )
                try persistRunResult(runResult, projectRoot: request.projectRoot, runDirectory: runDirectory)
                return runResult
            }
            if stage.requiresApproval {
                result = try applyApprovalGate(to: result, request: request)
            }
            try persistStageResult(
                result,
                projectRoot: request.projectRoot,
                runDirectory: runDirectory
            )
            stageResults.append(result)

            if result.status == .failed || result.status == .blocked {
                let runStatus = aggregateStatus(stageResults)
                let runResult = FlowRunResult(
                    runID: request.runID,
                    status: runStatus,
                    runDirectory: runDirectory,
                    stages: stageResults
                )
                try persistRunResult(runResult, projectRoot: request.projectRoot, runDirectory: runDirectory)
                return runResult
            }
        }

        let runResult = FlowRunResult(
            runID: request.runID,
            status: aggregateStatus(stageResults),
            runDirectory: runDirectory,
            stages: stageResults
        )
        try persistRunResult(runResult, projectRoot: request.projectRoot, runDirectory: runDirectory)
        return runResult
    }

    /// Judges the stage's "approval" gate from the run ledger's
    /// `approvals/{stageID}.json` record. The decision only matters on a
    /// stage that otherwise succeeded: approved keeps it succeeded,
    /// rejected fails it, and an absent record BLOCKS the run until the
    /// review cockpit records one — re-running the same runID then
    /// resumes past the gate.
    private func applyApprovalGate(
        to result: FlowStageResult,
        request: FlowOperationRequest
    ) throws -> FlowStageResult {
        var updated = result
        guard result.status == .succeeded else { return result }

        let record = try packageStore.loadApproval(
            runID: request.runID,
            stageID: result.stageID,
            inProjectAt: request.projectRoot
        )
        switch record?.verdict {
        case .approved:
            let diagnostic = FlowDiagnostic(
                severity: .info,
                code: "STAGE_APPROVED",
                message: "Approved by \(record?.reviewer ?? "unknown")\(record.map { $0.note.isEmpty ? "" : ": \($0.note)" } ?? "")."
            )
            updated.gates.append(FlowGateResult(
                gateID: "approval",
                status: .passed,
                diagnostics: [diagnostic]
            ))
            updated.diagnostics.append(diagnostic)
        case .rejected:
            let diagnostic = FlowDiagnostic(
                severity: .error,
                code: "STAGE_REJECTED",
                message: "Rejected by \(record?.reviewer ?? "unknown")\(record.map { $0.note.isEmpty ? "" : ": \($0.note)" } ?? "")."
            )
            updated.gates.append(FlowGateResult(
                gateID: "approval",
                status: .failed,
                diagnostics: [diagnostic]
            ))
            updated.diagnostics.append(diagnostic)
            updated.status = .failed
        case nil:
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
        }
        return updated
    }

    private func validate(request: FlowOperationRequest) throws {
        let validator = XcircuiteIdentifierValidator()
        try validator.validate(request.runID, kind: .runID)

        var stageIDs: Set<String> = []
        for stage in request.stages {
            try validator.validate(stage.stageID, kind: .stageID)
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
        code: String,
        message: String
    ) -> FlowStageResult {
        FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: [
                FlowDiagnostic(
                    severity: .error,
                    code: code,
                    message: message
                ),
            ]
        )
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
        runDirectory: URL
    ) throws {
        let runManifest = XcircuiteRunManifest(
            runID: result.runID,
            status: xcircuiteStatus(result.status),
            artifacts: result.stages.flatMap(\.artifacts)
        )
        try packageStore.writeJSON(
            runManifest,
            to: runDirectory.appending(path: "manifest.json"),
            forProjectAt: projectRoot
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

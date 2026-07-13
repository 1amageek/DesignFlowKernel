import Foundation
import ToolQualification

public struct DefaultFlowRunResumer: FlowRunResuming {
    private let loader: FlowRunLedgerLoading
    private let orchestrator: DefaultFlowOrchestrator
    private let inspector: FlowRunLedgerInspecting
    private let fileReferenceVerifier: XcircuiteFileReferenceVerifier

    public init(
        loader: FlowRunLedgerLoading = FlowRunLedgerLoader(),
        orchestrator: DefaultFlowOrchestrator = DefaultFlowOrchestrator(),
        inspector: FlowRunLedgerInspecting = DefaultFlowRunLedgerInspector(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.loader = loader
        self.orchestrator = orchestrator
        self.inspector = inspector
        self.fileReferenceVerifier = fileReferenceVerifier
    }

    public func resumeRun(
        request: FlowRunResumeRequest,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult],
        executors: [any FlowStageExecutor]
    ) async throws -> FlowRunResumeResult {
        try await resumeRun(
            request: request,
            toolRegistry: toolRegistry,
            healthResults: healthResults,
            executors: executors,
            toolchainProfile: nil
        )
    }

    public func resumeRun(
        request: FlowRunResumeRequest,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult],
        executors: [any FlowStageExecutor],
        toolchainProfile: FlowToolchainProfileRecord?
    ) async throws -> FlowRunResumeResult {
        let ledger = try loader.loadRunLedger(
            runID: request.runID,
            projectRoot: request.projectRoot
        )
        guard let plan = ledger.plan else {
            throw FlowRunResumeError.missingPlan(request.runID)
        }
        try validateResumableStatus(ledger)
        try validatePlanIntegrity(ledger, projectRoot: request.projectRoot)
        var operationRequest = plan.makeRequest(projectRoot: request.projectRoot)
        if operationRequest.toolchainProfile == nil {
            operationRequest.toolchainProfile = toolchainProfile
        }
        operationRequest.allowExistingRunDirectory = true

        let result = try await orchestrator.run(
            request: operationRequest,
            toolRegistry: toolRegistry,
            healthResults: healthResults,
            executors: executors
        )
        let summary = try inspector.inspectRun(
            runID: request.runID,
            projectRoot: request.projectRoot
        )
        return FlowRunResumeResult(result: result, summary: summary)
    }

    private func validateResumableStatus(_ ledger: FlowRunLedger) throws {
        // Blocked runs resume past a decided gate; failed runs resume as a
        // retry of the SAME persisted plan (the caller supplies repaired
        // executors/tools, the plan hash binding still rejects any plan
        // edit). Succeeded and cancelled runs stay final: finishing twice
        // would fork evidence, and cancellation is an explicit human stop.
        let status = ledger.runResult.status
        switch status {
        case .blocked, .failed:
            return
        case .created, .running, .succeeded, .cancelled, .partial:
            throw FlowRunResumeError.runStatusNotResumable(runID: ledger.runID, status: status)
        }
    }

    private func validatePlanIntegrity(
        _ ledger: FlowRunLedger,
        projectRoot: URL
    ) throws {
        let planPath = "\(XcircuitePackage.directoryName)/runs/\(ledger.runID)/plan.json"
        guard let reference = ledger.runManifest.artifacts.first(where: { $0.path == planPath }) else {
            throw FlowRunResumeError.missingPlanReference(ledger.runID)
        }
        let integrity = fileReferenceVerifier.verify(reference, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            throw FlowRunResumeError.invalidPlanReference(
                runID: ledger.runID,
                status: integrity.status
            )
        }
    }
}

import Foundation
import ToolQualification

public struct DefaultFlowRunResumer: FlowRunResuming {
    private let loader: FlowRunLedgerLoading
    private let orchestrator: DefaultFlowOrchestrator
    private let inspector: FlowRunLedgerInspecting
    private let artifactPersistence: any FlowArtifactPersisting

    public init(
        loader: FlowRunLedgerLoading,
        orchestrator: DefaultFlowOrchestrator,
        inspector: FlowRunLedgerInspecting,
        artifactPersistence: any FlowArtifactPersisting
    ) {
        self.loader = loader
        self.orchestrator = orchestrator
        self.inspector = inspector
        self.artifactPersistence = artifactPersistence
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
        let ledger = try await loader.loadRunLedger(
            runID: request.runID
        )
        guard let plan = ledger.plan else {
            throw FlowRunResumeError.missingPlan(request.runID)
        }
        try validateResumableStatus(ledger)
        try await validatePlanIntegrity(ledger, workspaceID: request.workspaceID)
        var operationRequest = plan.makeRequest(workspaceID: request.workspaceID)
        if operationRequest.toolchainProfile == nil {
            operationRequest.toolchainProfile = toolchainProfile
        }
        operationRequest.allowExistingRun = true

        let result = try await orchestrator.run(
            request: operationRequest,
            toolRegistry: toolRegistry,
            healthResults: healthResults,
            executors: executors
        )
        let summary = try await inspector.inspectRun(
            runID: request.runID,
            workspaceID: request.workspaceID
        )
        return FlowRunResumeResult(result: result, summary: summary)
    }

    private func validateResumableStatus(_ ledger: FlowRunLedger) throws {
        // Blocked runs resume past a decided gate; failed runs resume as a
        // retry of the SAME persisted plan (the caller supplies repaired
        // executors/tools, the plan hash binding still rejects any plan
        // edit). Succeeded and cancelled runs stay final: finishing twice
        // would fork evidence, and cancellation is an explicit human stop.
        let status = ledger.runManifest.status
        switch status {
        case .blocked, .failed:
            return
        case .created, .running, .succeeded, .cancelled, .partial:
            throw FlowRunResumeError.runStatusNotResumable(runID: ledger.runID, status: status)
        }
    }

    private func validatePlanIntegrity(
        _ ledger: FlowRunLedger,
        workspaceID: FlowWorkspaceID
    ) async throws {
        let planPath = "runs/\(ledger.runID)/plan.json"
        guard let reference = ledger.runManifest.artifacts.first(where: {
            $0.id.rawValue == "run-plan" || $0.path == planPath
        }) else {
            throw FlowRunResumeError.missingPlanReference(ledger.runID)
        }
        do {
            _ = try await artifactPersistence.loadArtifactContent(
                for: reference
            )
        } catch {
            throw FlowRunResumeError.invalidPlanReference(
                runID: ledger.runID,
                status: .unreadableArtifact
            )
        }
    }
}

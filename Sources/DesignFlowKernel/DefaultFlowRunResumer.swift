import Foundation
import ToolQualification

public struct DefaultFlowRunResumer: FlowRunResuming {
    private let loader: FlowRunLedgerLoading
    private let orchestrator: DefaultFlowOrchestrator
    private let inspector: FlowRunLedgerInspecting
    private let artifactPersistence: any FlowArtifactPersisting
    private let artifactLocationValidator: any FlowRunArtifactLocationValidator

    public init(
        loader: FlowRunLedgerLoading,
        orchestrator: DefaultFlowOrchestrator,
        inspector: FlowRunLedgerInspecting,
        artifactPersistence: any FlowArtifactPersisting,
        artifactLocationValidator: any FlowRunArtifactLocationValidator = DefaultFlowRunArtifactLocationValidator()
    ) {
        self.loader = loader
        self.orchestrator = orchestrator
        self.inspector = inspector
        self.artifactPersistence = artifactPersistence
        self.artifactLocationValidator = artifactLocationValidator
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
            toolchainProfile: nil,
            artifactPreparer: nil
        )
    }

    public func resumeRun(
        request: FlowRunResumeRequest,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult],
        executors: [any FlowStageExecutor],
        toolchainProfile: FlowToolchainProfileRecord?,
        artifactPreparer: (any FlowRunArtifactPreparing)? = nil
    ) async throws -> FlowRunResumeResult {
        let ledger = try await loader.loadRunLedger(
            runID: request.runID
        )
        guard let plan = ledger.plan else {
            throw FlowRunResumeError.missingPlan(request.runID)
        }
        try validateResumableStatus(ledger)
        try await validatePlanIntegrity(ledger)
        var operationRequest = plan.makeRequest(workspaceID: request.workspaceID)
        if operationRequest.toolchainProfile == nil {
            operationRequest.toolchainProfile = toolchainProfile
        }
        operationRequest.allowExistingRun = true

        let result = try await orchestrator.run(
            request: operationRequest,
            toolRegistry: toolRegistry,
            healthResults: healthResults,
            executors: executors,
            artifactPreparer: artifactPreparer
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

    private func validatePlanIntegrity(_ ledger: FlowRunLedger) async throws {
        let planPath = "runs/\(ledger.runID)/plan.json"
        let candidates = ledger.runManifest.artifacts.filter {
            $0.id.rawValue == "run-plan"
        }
        let references = candidates.filter {
            artifactLocationValidator.isReference(
                $0,
                boundTo: planPath,
                allowingContentAddressedVariant: false
            )
                && $0.locator.role == .input
                && $0.locator.kind == .other
                && $0.locator.format == .json
        }
        guard candidates.count == 1,
              references.count == 1,
              let reference = references.first else {
            throw FlowRunResumeError.missingPlanReference(ledger.runID)
        }
        do {
            let content = try await artifactPersistence.loadArtifactContent(
                for: reference
            )
            let retainedPlan = try JSONDecoder().decode(FlowRunPlan.self, from: content)
            guard retainedPlan == ledger.plan else {
                throw FlowRunResumeError.planProjectionMismatch(ledger.runID)
            }
        } catch let error as FlowRunResumeError {
            throw error
        } catch {
            throw FlowRunResumeError.invalidPlanReference(
                runID: ledger.runID,
                status: .unreadableArtifact
            )
        }
    }
}

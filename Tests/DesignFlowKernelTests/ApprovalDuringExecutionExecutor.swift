import DesignFlowKernel

struct ApprovalDuringExecutionExecutor: FlowStageExecutor {
    let stageID: String
    let toolID: String
    let approvalRecorder: any FlowGateApprovalRecording

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        _ = try await approvalRecorder.recordApproval(
            FlowGateApprovalRequest(
                workspaceID: context.workspaceID,
                runID: context.runID,
                stageID: stage.stageID,
                verdict: .approved,
                reviewer: "reviewer-1"
            )
        )
        return FlowStageResult(
            stageID: stage.stageID,
            status: .succeeded
        )
    }
}

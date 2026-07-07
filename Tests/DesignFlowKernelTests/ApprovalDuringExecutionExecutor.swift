import DesignFlowKernel

struct ApprovalDuringExecutionExecutor: FlowStageExecutor {
    let stageID: String
    let toolID: String

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        _ = try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: context.projectRoot,
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

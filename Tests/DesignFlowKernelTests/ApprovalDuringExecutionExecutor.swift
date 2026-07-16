import DesignFlowKernel

struct ApprovalDuringExecutionExecutor: FlowStageExecutor {
    let stageID: String
    let toolID: String

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        let infrastructure = await TestFlowInfrastructure.bound(to: context.projectRoot)
        _ = try await DefaultFlowGateApprovalRecorder(
            loader: infrastructure,
            inspector: DefaultFlowRunLedgerInspector(
                reviewBundler: DefaultFlowRunReviewBundler(
                    loader: infrastructure,
                    persistence: infrastructure
                )
            ),
            ledgerPersistence: infrastructure
        ).recordApproval(
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

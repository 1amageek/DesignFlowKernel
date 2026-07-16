public protocol FlowRunControlLoading: Sendable {
    func loadApproval(
        runID: String,
        stageID: String
    ) async throws -> FlowApprovalRecord?

    func loadCancellationRequest(
        runID: String
    ) async throws -> FlowRunCancellationRequest?
}

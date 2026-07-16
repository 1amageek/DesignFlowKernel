public protocol FlowRunLedgerLoading: Sendable {
    func loadRunLedger(runID: String) async throws -> FlowRunLedger
}

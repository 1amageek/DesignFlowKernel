import Foundation

public protocol FlowRunLedgerLoading: Sendable {
    func loadRunLedger(runID: String, projectRoot: URL) throws -> FlowRunLedger
}

import Foundation

public protocol FlowRunLedgerInspecting: Sendable {
    func inspectRun(runID: String, projectRoot: URL) throws -> FlowRunLedgerSummary
}

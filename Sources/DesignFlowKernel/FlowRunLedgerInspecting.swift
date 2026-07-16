import Foundation

public protocol FlowRunLedgerInspecting: Sendable {
    func inspectRun(runID: String, projectRoot: URL) async throws -> FlowRunLedgerSummary
}

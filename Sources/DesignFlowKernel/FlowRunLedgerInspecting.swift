import Foundation

public protocol FlowRunLedgerInspecting: Sendable {
    func inspectRun(runID: String, workspaceID: FlowWorkspaceID) async throws -> FlowRunLedgerSummary
}

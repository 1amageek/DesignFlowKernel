import Foundation

/// Asynchronous persistence boundary for flow lifecycle state.
///
/// Implementations own their storage format and filesystem/database details.
/// The kernel only exchanges typed run records and integrity failures, which
/// keeps `.xcircuite` storage out of the orchestration layer.
public protocol FlowRunLedgerPersisting: Sendable {
    func loadRunLedger(runID: String, projectRoot: URL) async throws -> FlowRunLedger
    func saveRunLedger(_ ledger: FlowRunLedger, projectRoot: URL) async throws
}

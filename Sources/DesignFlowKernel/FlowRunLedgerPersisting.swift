import Foundation

/// Asynchronous persistence boundary for flow lifecycle state.
///
/// Implementations own their storage format and filesystem/database details.
/// The kernel only exchanges typed run records and integrity failures, which
/// keeps concrete workspace storage out of the orchestration layer.
public protocol FlowRunLedgerPersisting: FlowRunLedgerLoading {
    func saveRunLedger(_ ledger: FlowRunLedger) async throws
}

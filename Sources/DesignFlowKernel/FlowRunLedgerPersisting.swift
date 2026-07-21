import Foundation

/// Asynchronous persistence boundary for flow lifecycle state.
///
/// Implementations own their storage format and filesystem/database details.
/// The kernel only exchanges typed run records and integrity failures, which
/// keeps concrete workspace storage out of the orchestration layer.
public protocol FlowRunLedgerPersisting: FlowRunLedgerLoading {
    /// Creates the initial ledger only when the run identifier is absent.
    ///
    /// Implementations must perform the existence check and write as one
    /// atomic storage operation. A load followed by `saveRunLedger` does not
    /// satisfy this contract because concurrent creators could both succeed.
    func createRunLedger(_ ledger: FlowRunLedger) async throws -> FlowRunLedger
    func saveRunLedger(_ ledger: FlowRunLedger) async throws -> FlowRunLedger
}

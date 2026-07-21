import CircuiteFoundation
import Foundation

/// Atomically appends an immutable action-owned artifact and its ledger action.
///
/// Action artifacts are decision and review evidence. They remain separate
/// from immutable stage-analysis artifacts and the terminal evidence manifest.
public protocol FlowRunActionArtifactPersisting: FlowRunLedgerPersisting {
    @discardableResult
    func appendActionArtifact(
        content: Data,
        reference: ArtifactReference,
        action: FlowRunActionRecord
    ) async throws -> FlowRunLedger
}

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
        logicalID: String,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor,
        producer: ProducerIdentity?,
        action: FlowRunActionRecord
    ) async throws -> FlowRunLedger
}

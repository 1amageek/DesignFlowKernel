import CircuiteFoundation
import Foundation

/// Retains reviewed evidence and atomically appends an immutable approval
/// artifact, approval record, and action bound to that evidence.
public protocol FlowRunApprovalArtifactPersisting: FlowRunActionArtifactPersisting {
    func loadArtifactContent(for reference: ArtifactReference) async throws -> Data

    @discardableResult
    func appendApprovalArtifact(
        content: Data,
        reference: ArtifactReference,
        approval: FlowApprovalRecord,
        action: FlowRunActionRecord
    ) async throws -> FlowRunLedger
}

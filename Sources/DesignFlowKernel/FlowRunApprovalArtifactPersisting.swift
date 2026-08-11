import CircuiteFoundation
import Foundation

/// Retains reviewed evidence and atomically appends an immutable approval
/// artifact, approval record, and action bound to that evidence.
public protocol FlowRunApprovalArtifactPersisting: FlowRunActionArtifactPersisting {
    func loadArtifactContent(for artifact: FlowArtifactBinding) async throws -> Data

    @discardableResult
    func appendApprovalArtifact(
        content: Data,
        logicalID: String,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor,
        producer: ProducerIdentity?,
        approval: FlowApprovalRecord,
        action: FlowRunActionRecord
    ) async throws -> FlowRunLedger
}

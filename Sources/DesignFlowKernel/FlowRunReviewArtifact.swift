import Foundation
import CircuiteFoundation

public struct FlowRunReviewArtifact: Sendable, Hashable, Codable {
    /// The canonical artifact identity, location, format, and integrity claims.
    public var reference: ArtifactReference

    /// The artifact's purpose within a flow review. This is flow metadata and
    /// is intentionally distinct from the producer-defined locator role.
    public var purpose: FlowRunReviewArtifactPurpose
    public var stageID: String?
    public var integrity: FlowRunReviewArtifactIntegrity?

    public init(
        reference: ArtifactReference,
        purpose: FlowRunReviewArtifactPurpose,
        stageID: String? = nil,
        integrity: FlowRunReviewArtifactIntegrity? = nil
    ) {
        self.reference = reference
        self.purpose = purpose
        self.stageID = stageID
        self.integrity = integrity
    }
}

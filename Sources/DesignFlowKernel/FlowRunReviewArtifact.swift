import Foundation
import CircuiteFoundation

public struct FlowRunReviewArtifact: Sendable, Hashable, Codable {
    /// The canonical content identity and independently resolved availability.
    public var binding: FlowArtifactBinding

    public var reference: ArtifactReference { binding.reference }

    /// The artifact's purpose within a flow review. This is flow metadata and
    /// is intentionally distinct from the producer-defined locator role.
    public var purpose: FlowRunReviewArtifactPurpose
    public var stageID: String?
    public var integrity: FlowRunReviewArtifactIntegrity?

    public init(
        binding: FlowArtifactBinding,
        purpose: FlowRunReviewArtifactPurpose,
        stageID: String? = nil,
        integrity: FlowRunReviewArtifactIntegrity? = nil
    ) {
        self.binding = binding
        self.purpose = purpose
        self.stageID = stageID
        self.integrity = integrity
    }
}

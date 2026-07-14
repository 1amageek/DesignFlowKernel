import CircuiteFoundation
import Foundation

public struct FlowRunReleaseRetentionIndexBuildResult: Sendable, Hashable, Codable {
    public var index: FlowRunReleaseRetentionIndex
    /// Canonical Foundation reference for the persisted retention index.
    public var artifact: ArtifactReference

    public init(
        index: FlowRunReleaseRetentionIndex,
        artifact: ArtifactReference
    ) {
        self.index = index
        self.artifact = artifact
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(FlowRunReleaseRetentionIndex.self, forKey: .index)
        do {
            artifact = try container.decode(ArtifactReference.self, forKey: .artifact)
        } catch {
            let legacy = try container.decode(XcircuiteFileReference.self, forKey: .artifact)
            artifact = try legacy.foundationArtifactReference()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case artifact
    }
}

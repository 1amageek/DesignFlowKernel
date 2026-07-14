import CircuiteFoundation
import Foundation

public struct FlowRunStageArtifactLadderBuildResult: Sendable, Hashable, Codable {
    public var ladder: FlowRunStageArtifactLadder
    /// Canonical Foundation reference for the persisted artifact ladder.
    public var artifact: ArtifactReference

    public init(
        ladder: FlowRunStageArtifactLadder,
        artifact: ArtifactReference
    ) {
        self.ladder = ladder
        self.artifact = artifact
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ladder = try container.decode(FlowRunStageArtifactLadder.self, forKey: .ladder)
        artifact = try container.decode(ArtifactReference.self, forKey: .artifact)
    }

    private enum CodingKeys: String, CodingKey {
        case ladder
        case artifact
    }
}

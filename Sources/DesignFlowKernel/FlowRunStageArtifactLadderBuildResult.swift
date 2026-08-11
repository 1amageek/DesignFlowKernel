import CircuiteFoundation
import Foundation

public struct FlowRunStageArtifactLadderBuildResult: Sendable, Hashable, Codable {
    public var ladder: FlowRunStageArtifactLadder
    /// Canonical content identity and materialization for the persisted artifact ladder.
    public var artifact: FlowArtifactBinding

    public init(
        ladder: FlowRunStageArtifactLadder,
        artifact: FlowArtifactBinding
    ) {
        self.ladder = ladder
        self.artifact = artifact
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ladder = try container.decode(FlowRunStageArtifactLadder.self, forKey: .ladder)
        artifact = try container.decode(FlowArtifactBinding.self, forKey: .artifact)
    }

    private enum CodingKeys: String, CodingKey {
        case ladder
        case artifact
    }
}

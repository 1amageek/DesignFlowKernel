import CircuiteFoundation
import Foundation

public struct FlowRunDecisionPacketBuildResult: Sendable, Hashable, Codable {
    public var packet: FlowRunDecisionPacket
    public var artifact: FlowArtifactBinding

    public init(
        packet: FlowRunDecisionPacket,
        artifact: FlowArtifactBinding
    ) {
        self.packet = packet
        self.artifact = artifact
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packet = try container.decode(FlowRunDecisionPacket.self, forKey: .packet)
        artifact = try container.decode(FlowArtifactBinding.self, forKey: .artifact)
    }

    private enum CodingKeys: String, CodingKey {
        case packet
        case artifact
    }
}

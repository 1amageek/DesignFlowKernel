import CircuiteFoundation
import Foundation

public struct FlowRunDecisionPacketBuildResult: Sendable, Hashable, Codable {
    public var packet: FlowRunDecisionPacket
    /// Canonical Foundation reference for the persisted decision packet.
    public var artifact: ArtifactReference

    public init(
        packet: FlowRunDecisionPacket,
        artifact: ArtifactReference
    ) {
        self.packet = packet
        self.artifact = artifact
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packet = try container.decode(FlowRunDecisionPacket.self, forKey: .packet)
        artifact = try container.decode(ArtifactReference.self, forKey: .artifact)
    }

    private enum CodingKeys: String, CodingKey {
        case packet
        case artifact
    }
}

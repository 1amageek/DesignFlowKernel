import Foundation

public struct FlowRunDecisionPacketBuildResult: Sendable, Hashable, Codable {
    public var packet: FlowRunDecisionPacket
    public var artifact: XcircuiteFileReference

    public init(
        packet: FlowRunDecisionPacket,
        artifact: XcircuiteFileReference
    ) {
        self.packet = packet
        self.artifact = artifact
    }
}

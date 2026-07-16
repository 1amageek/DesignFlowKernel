import Foundation

public protocol FlowRunDecisionPacketBuilding: Sendable {
    func buildDecisionPacket(
        runID: String,
        projectRoot: URL
    ) async throws -> FlowRunDecisionPacketBuildResult
}

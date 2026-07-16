import Foundation

public protocol FlowRunDecisionPacketBuilding: Sendable {
    func buildDecisionPacket(
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws -> FlowRunDecisionPacketBuildResult
}

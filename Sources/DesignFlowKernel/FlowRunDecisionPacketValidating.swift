import Foundation

public protocol FlowRunDecisionPacketValidating: Sendable {
    func validateDecisionPacket(
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws -> FlowRunDecisionPacketValidationResult
}

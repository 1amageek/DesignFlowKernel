import Foundation

public protocol FlowRunStageArtifactLadderBuilding: Sendable {
    func makeStageArtifactLadder(
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws -> FlowRunStageArtifactLadder

    func buildStageArtifactLadder(
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws -> FlowRunStageArtifactLadderBuildResult
}

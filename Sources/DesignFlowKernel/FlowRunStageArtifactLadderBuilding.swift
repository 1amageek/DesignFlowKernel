import Foundation

public protocol FlowRunStageArtifactLadderBuilding: Sendable {
    func makeStageArtifactLadder(
        runID: String,
        projectRoot: URL
    ) async throws -> FlowRunStageArtifactLadder

    func buildStageArtifactLadder(
        runID: String,
        projectRoot: URL
    ) async throws -> FlowRunStageArtifactLadderBuildResult
}

import Foundation

public protocol FlowRunStageArtifactLadderBuilding: Sendable {
    func makeStageArtifactLadder(
        runID: String,
        projectRoot: URL
    ) throws -> FlowRunStageArtifactLadder

    func buildStageArtifactLadder(
        runID: String,
        projectRoot: URL
    ) throws -> FlowRunStageArtifactLadderBuildResult
}

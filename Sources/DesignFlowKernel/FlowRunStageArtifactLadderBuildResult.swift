import Foundation

public struct FlowRunStageArtifactLadderBuildResult: Sendable, Hashable, Codable {
    public var ladder: FlowRunStageArtifactLadder
    public var artifact: XcircuiteFileReference

    public init(
        ladder: FlowRunStageArtifactLadder,
        artifact: XcircuiteFileReference
    ) {
        self.ladder = ladder
        self.artifact = artifact
    }
}

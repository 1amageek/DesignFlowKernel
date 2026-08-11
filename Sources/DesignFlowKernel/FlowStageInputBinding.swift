public struct FlowStageInputBinding: Sendable, Hashable, Codable {
    public let stageID: String
    public let artifacts: [FlowArtifactBinding]

    public init(stageID: String, artifacts: [FlowArtifactBinding]) {
        self.stageID = stageID
        self.artifacts = artifacts
    }
}

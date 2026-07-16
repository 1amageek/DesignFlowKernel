import Foundation

public struct FlowToolchainManifest: Sendable, Hashable, Codable {
    @FlowSchemaVersion1 public var schemaVersion: Int
    public var runID: String
    public var profile: FlowToolchainProfileRecord?
    public var stages: [FlowToolchainStageRecord]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        profile: FlowToolchainProfileRecord? = nil,
        stages: [FlowToolchainStageRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.profile = profile
        self.stages = stages
    }
}

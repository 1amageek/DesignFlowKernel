import Foundation

public struct FlowToolchainStageRawArtifactRecord: Sendable, Hashable, Codable {
    public var stageID: String
    public var relativePath: String

    public init(stageID: String, relativePath: String) {
        self.stageID = stageID
        self.relativePath = relativePath
    }
}

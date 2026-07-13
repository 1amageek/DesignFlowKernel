import CircuiteFoundation
import Foundation

public struct FlowToolchainStageArtifactSelectorRecord: Sendable, Hashable, Codable {
    public var stageID: String
    public var artifactID: String?
    public var kind: ArtifactKind?
    public var format: ArtifactFormat?
    public var pathSuffix: String?

    public init(
        stageID: String,
        artifactID: String? = nil,
        kind: ArtifactKind? = nil,
        format: ArtifactFormat? = nil,
        pathSuffix: String? = nil
    ) {
        self.stageID = stageID
        self.artifactID = artifactID
        self.kind = kind
        self.format = format
        self.pathSuffix = pathSuffix
    }
}

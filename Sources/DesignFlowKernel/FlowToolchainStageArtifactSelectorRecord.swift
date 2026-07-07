import Foundation
import XcircuitePackage

public struct FlowToolchainStageArtifactSelectorRecord: Sendable, Hashable, Codable {
    public var stageID: String
    public var artifactID: String?
    public var kind: XcircuiteFileKind?
    public var format: XcircuiteFileFormat?
    public var pathSuffix: String?

    public init(
        stageID: String,
        artifactID: String? = nil,
        kind: XcircuiteFileKind? = nil,
        format: XcircuiteFileFormat? = nil,
        pathSuffix: String? = nil
    ) {
        self.stageID = stageID
        self.artifactID = artifactID
        self.kind = kind
        self.format = format
        self.pathSuffix = pathSuffix
    }
}

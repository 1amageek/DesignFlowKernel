import Foundation
import XcircuitePackage

public struct FlowRunReleaseRetentionIndexBuildResult: Sendable, Hashable, Codable {
    public var index: FlowRunReleaseRetentionIndex
    public var artifact: XcircuiteFileReference

    public init(
        index: FlowRunReleaseRetentionIndex,
        artifact: XcircuiteFileReference
    ) {
        self.index = index
        self.artifact = artifact
    }
}

import Foundation
import XcircuitePackage

public struct FlowRunReleaseEnvelopeBuildResult: Sendable, Hashable, Codable {
    public var envelope: FlowRunReleaseEnvelope
    public var artifact: XcircuiteFileReference

    public init(
        envelope: FlowRunReleaseEnvelope,
        artifact: XcircuiteFileReference
    ) {
        self.envelope = envelope
        self.artifact = artifact
    }
}

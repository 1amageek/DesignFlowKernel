import CircuiteFoundation
import Foundation

public struct FlowRunReleaseEnvelopeBuildResult: Sendable, Hashable, Codable {
    public var envelope: FlowRunReleaseEnvelope
    public var artifact: ArtifactReference

    public init(
        envelope: FlowRunReleaseEnvelope,
        artifact: ArtifactReference
    ) {
        self.envelope = envelope
        self.artifact = artifact
    }
}

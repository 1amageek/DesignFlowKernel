import CircuiteFoundation
import Foundation

public struct FlowRunReleaseEnvelopeBuildResult: Sendable, Hashable, Codable {
    public var envelope: FlowRunReleaseEnvelope
    public var artifact: FlowArtifactBinding

    public init(
        envelope: FlowRunReleaseEnvelope,
        artifact: FlowArtifactBinding
    ) {
        self.envelope = envelope
        self.artifact = artifact
    }
}

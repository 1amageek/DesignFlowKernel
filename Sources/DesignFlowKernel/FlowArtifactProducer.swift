import CircuiteFoundation
import Foundation

public struct FlowArtifactProducer: Sendable, Hashable, Codable {
    public var identity: ProducerIdentity
    public var command: [String]
    public var environmentDigest: String?
    public var generatedAt: String?

    public init(
        identity: ProducerIdentity,
        command: [String] = [],
        environmentDigest: String? = nil,
        generatedAt: String? = nil
    ) {
        self.identity = identity
        self.command = command
        self.environmentDigest = environmentDigest
        self.generatedAt = generatedAt
    }
}

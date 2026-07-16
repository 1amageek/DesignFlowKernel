import Foundation

public struct FlowArtifactEnvelopeRecord: Sendable, Hashable, Codable {
    public var envelope: FlowArtifactEnvelope
    public var persistedAt: Date

    public init(envelope: FlowArtifactEnvelope, persistedAt: Date) {
        self.envelope = envelope
        self.persistedAt = persistedAt
    }
}

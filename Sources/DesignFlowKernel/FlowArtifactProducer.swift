import Foundation

public struct FlowArtifactProducer: Sendable, Hashable, Codable {
    public var producerID: String
    public var toolID: String?
    public var toolVersion: String?
    public var command: [String]
    public var environmentDigest: String?
    public var generatedAt: String?

    public init(
        producerID: String,
        toolID: String? = nil,
        toolVersion: String? = nil,
        command: [String] = [],
        environmentDigest: String? = nil,
        generatedAt: String? = nil
    ) {
        self.producerID = producerID
        self.toolID = toolID
        self.toolVersion = toolVersion
        self.command = command
        self.environmentDigest = environmentDigest
        self.generatedAt = generatedAt
    }
}

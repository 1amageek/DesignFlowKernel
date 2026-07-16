import Foundation

public struct FlowEngineCapability: Sendable, Hashable, Codable {
    public var engineID: String
    public var contractVersion: Int
    public var supportedInputFormats: [ArtifactFormat]
    public var supportedOutputFormats: [ArtifactFormat]
    public var features: [String]
    public var limitations: [String]

    public init(
        engineID: String,
        contractVersion: Int,
        supportedInputFormats: [ArtifactFormat],
        supportedOutputFormats: [ArtifactFormat],
        features: [String] = [],
        limitations: [String] = []
    ) {
        self.engineID = engineID
        self.contractVersion = contractVersion
        self.supportedInputFormats = supportedInputFormats
        self.supportedOutputFormats = supportedOutputFormats
        self.features = features
        self.limitations = limitations
    }
}

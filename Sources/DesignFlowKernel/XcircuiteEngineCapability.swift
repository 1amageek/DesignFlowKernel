import Foundation

public struct XcircuiteEngineCapability: Sendable, Hashable, Codable {
    public var engineID: String
    public var contractVersion: Int
    public var supportedInputFormats: [XcircuiteFileFormat]
    public var supportedOutputFormats: [XcircuiteFileFormat]
    public var features: [String]
    public var limitations: [String]

    public init(
        engineID: String,
        contractVersion: Int,
        supportedInputFormats: [XcircuiteFileFormat],
        supportedOutputFormats: [XcircuiteFileFormat],
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

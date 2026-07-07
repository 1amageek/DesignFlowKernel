import Foundation

public struct FlowToolchainInlineTechnologyRecord: Sendable, Hashable, Codable {
    public var processName: String
    public var layerCount: Int
    public var viaCount: Int
    public var logicalLayerCount: Int
    public var backendHintKeys: [String]

    public init(
        processName: String,
        layerCount: Int,
        viaCount: Int,
        logicalLayerCount: Int,
        backendHintKeys: [String] = []
    ) {
        self.processName = processName
        self.layerCount = layerCount
        self.viaCount = viaCount
        self.logicalLayerCount = logicalLayerCount
        self.backendHintKeys = backendHintKeys
    }
}

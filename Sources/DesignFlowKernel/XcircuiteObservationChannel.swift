import Foundation

public struct XcircuiteObservationChannel: Sendable, Hashable, Codable {
    public var channelID: String
    public var label: String?
    public var status: XcircuiteObservationChannelStatus
    public var value: XcircuiteJSONValue?
    public var unit: String?
    public var sourceArtifactIDs: [String]
    public var confidence: XcircuiteEvidenceConfidence?
    public var metadata: [String: XcircuiteJSONValue]

    public init(
        channelID: String,
        label: String? = nil,
        status: XcircuiteObservationChannelStatus,
        value: XcircuiteJSONValue? = nil,
        unit: String? = nil,
        sourceArtifactIDs: [String] = [],
        confidence: XcircuiteEvidenceConfidence? = nil,
        metadata: [String: XcircuiteJSONValue] = [:]
    ) {
        self.channelID = channelID
        self.label = label
        self.status = status
        self.value = value
        self.unit = unit
        self.sourceArtifactIDs = sourceArtifactIDs
        self.confidence = confidence
        self.metadata = metadata
    }
}

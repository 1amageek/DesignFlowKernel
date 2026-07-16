import Foundation

public struct FlowObservationChannel: Sendable, Hashable, Codable {
    public var channelID: String
    public var label: String?
    public var status: FlowObservationChannelStatus
    public var value: FlowMetricValue?
    public var unit: String?
    public var sourceArtifactIDs: [String]
    public var confidence: FlowEvidenceConfidence?
    public var context: FlowEvaluationContext?

    public init(
        channelID: String,
        label: String? = nil,
        status: FlowObservationChannelStatus,
        value: FlowMetricValue? = nil,
        unit: String? = nil,
        sourceArtifactIDs: [String] = [],
        confidence: FlowEvidenceConfidence? = nil,
        context: FlowEvaluationContext? = nil
    ) {
        self.channelID = channelID
        self.label = label
        self.status = status
        self.value = value
        self.unit = unit
        self.sourceArtifactIDs = sourceArtifactIDs
        self.confidence = confidence
        self.context = context
    }
}

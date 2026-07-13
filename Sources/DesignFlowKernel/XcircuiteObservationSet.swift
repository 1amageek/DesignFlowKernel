import Foundation

public struct XcircuiteObservationSet: Sendable, Hashable, Codable {
    public var observationSetID: String
    public var specID: String?
    public var channels: [XcircuiteObservationChannel]
    public var confidence: XcircuiteEvidenceConfidence?
    public var generatedAt: String?
    public var metadata: [String: XcircuiteJSONValue]

    public var observedChannelIDs: [String] {
        channels
            .filter { $0.status == .observed || $0.status == .derived }
            .map(\.channelID)
    }

    public var missingChannelIDs: [String] {
        channels
            .filter { $0.status == .missing }
            .map(\.channelID)
    }

    public var uncalibratedChannelIDs: [String] {
        channels
            .filter { $0.status == .uncalibrated }
            .map(\.channelID)
    }

    public init(
        observationSetID: String,
        specID: String? = nil,
        channels: [XcircuiteObservationChannel] = [],
        confidence: XcircuiteEvidenceConfidence? = nil,
        generatedAt: String? = nil,
        metadata: [String: XcircuiteJSONValue] = [:]
    ) {
        self.observationSetID = observationSetID
        self.specID = specID
        self.channels = channels
        self.confidence = confidence
        self.generatedAt = generatedAt
        self.metadata = metadata
    }
}

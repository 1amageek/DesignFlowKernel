import Foundation

public struct FlowObservationSet: Sendable, Hashable, Codable {
    public var observationSetID: String
    public var specID: String?
    public var channels: [FlowObservationChannel]
    public var confidence: FlowEvidenceConfidence?
    public var generatedAt: String?

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
        channels: [FlowObservationChannel] = [],
        confidence: FlowEvidenceConfidence? = nil,
        generatedAt: String? = nil
    ) {
        self.observationSetID = observationSetID
        self.specID = specID
        self.channels = channels
        self.confidence = confidence
        self.generatedAt = generatedAt
    }
}

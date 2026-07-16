import Foundation

public struct FlowEvaluationResult: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var evaluationID: String
    public var specID: String
    public var status: FlowEvaluationStatus
    public var likelihood: Double?
    public var residual: Double?
    public var confidence: FlowEvidenceConfidence?
    public var channelResults: [FlowEvaluationChannelResult]
    public var feedbackSignals: [FlowFeedbackSignal]
    public var summary: String

    public init(
        schemaVersion: Int = 1,
        evaluationID: String,
        specID: String,
        status: FlowEvaluationStatus,
        likelihood: Double? = nil,
        residual: Double? = nil,
        confidence: FlowEvidenceConfidence? = nil,
        channelResults: [FlowEvaluationChannelResult] = [],
        feedbackSignals: [FlowFeedbackSignal] = [],
        summary: String
    ) {
        self.schemaVersion = schemaVersion
        self.evaluationID = evaluationID
        self.specID = specID
        self.status = status
        self.likelihood = likelihood
        self.residual = residual
        self.confidence = confidence
        self.channelResults = channelResults
        self.feedbackSignals = feedbackSignals
        self.summary = summary
    }
}

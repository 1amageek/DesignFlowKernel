import Foundation

public struct XcircuiteEvaluationResult: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var evaluationID: String
    public var specID: String
    public var status: XcircuiteEvaluationStatus
    public var likelihood: Double?
    public var residual: Double?
    public var confidence: XcircuiteEvidenceConfidence?
    public var channelResults: [XcircuiteEvaluationChannelResult]
    public var feedbackSignals: [XcircuiteFeedbackSignal]
    public var summary: String
    public var metadata: [String: XcircuiteJSONValue]

    public init(
        schemaVersion: Int = 1,
        evaluationID: String,
        specID: String,
        status: XcircuiteEvaluationStatus,
        likelihood: Double? = nil,
        residual: Double? = nil,
        confidence: XcircuiteEvidenceConfidence? = nil,
        channelResults: [XcircuiteEvaluationChannelResult] = [],
        feedbackSignals: [XcircuiteFeedbackSignal] = [],
        summary: String,
        metadata: [String: XcircuiteJSONValue] = [:]
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
        self.metadata = metadata
    }
}

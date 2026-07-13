import Foundation

public struct XcircuiteFeedbackSignal: Sendable, Hashable, Codable {
    public var signalID: String
    public var sourceEvaluationID: String?
    public var channelID: String?
    public var routingLevel: XcircuiteFeedbackRoutingLevel
    public var severity: XcircuiteFeedbackSeverity
    public var summary: String
    public var residual: Double?
    public var affectedArtifactIDs: [String]
    public var affectedPaths: [String]
    public var suggestedActions: [String]
    public var confidence: XcircuiteEvidenceConfidence?
    public var metadata: [String: XcircuiteJSONValue]

    public init(
        signalID: String,
        sourceEvaluationID: String? = nil,
        channelID: String? = nil,
        routingLevel: XcircuiteFeedbackRoutingLevel,
        severity: XcircuiteFeedbackSeverity,
        summary: String,
        residual: Double? = nil,
        affectedArtifactIDs: [String] = [],
        affectedPaths: [String] = [],
        suggestedActions: [String] = [],
        confidence: XcircuiteEvidenceConfidence? = nil,
        metadata: [String: XcircuiteJSONValue] = [:]
    ) {
        self.signalID = signalID
        self.sourceEvaluationID = sourceEvaluationID
        self.channelID = channelID
        self.routingLevel = routingLevel
        self.severity = severity
        self.summary = summary
        self.residual = residual
        self.affectedArtifactIDs = affectedArtifactIDs
        self.affectedPaths = affectedPaths
        self.suggestedActions = suggestedActions
        self.confidence = confidence
        self.metadata = metadata
    }
}

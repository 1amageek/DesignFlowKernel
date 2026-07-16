import Foundation

public struct FlowFeedbackSignal: Sendable, Hashable, Codable {
    public var signalID: String
    public var sourceEvaluationID: String?
    public var channelID: String?
    public var routingLevel: FlowFeedbackRoutingLevel
    public var severity: FlowFeedbackSeverity
    public var summary: String
    public var residual: Double?
    public var affectedArtifactIDs: [String]
    public var affectedPaths: [String]
    public var suggestedActions: [String]
    public var confidence: FlowEvidenceConfidence?

    public init(
        signalID: String,
        sourceEvaluationID: String? = nil,
        channelID: String? = nil,
        routingLevel: FlowFeedbackRoutingLevel,
        severity: FlowFeedbackSeverity,
        summary: String,
        residual: Double? = nil,
        affectedArtifactIDs: [String] = [],
        affectedPaths: [String] = [],
        suggestedActions: [String] = [],
        confidence: FlowEvidenceConfidence? = nil
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
    }
}

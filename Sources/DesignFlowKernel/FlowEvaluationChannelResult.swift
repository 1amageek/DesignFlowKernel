import Foundation

public struct FlowEvaluationChannelResult: Sendable, Hashable, Codable {
    public var criterionID: String?
    public var channelID: String
    public var status: FlowEvaluationStatus
    public var observedValue: FlowMetricValue?
    public var residual: Double?
    public var likelihood: Double?
    public var confidence: FlowEvidenceConfidence?
    public var diagnostics: [FlowRunDiagnostic]
    public var context: FlowEvaluationContext?

    public init(
        criterionID: String? = nil,
        channelID: String,
        status: FlowEvaluationStatus,
        observedValue: FlowMetricValue? = nil,
        residual: Double? = nil,
        likelihood: Double? = nil,
        confidence: FlowEvidenceConfidence? = nil,
        diagnostics: [FlowRunDiagnostic] = [],
        context: FlowEvaluationContext? = nil
    ) {
        self.criterionID = criterionID
        self.channelID = channelID
        self.status = status
        self.observedValue = observedValue
        self.residual = residual
        self.likelihood = likelihood
        self.confidence = confidence
        self.diagnostics = diagnostics
        self.context = context
    }
}

import Foundation

public struct XcircuiteEvaluationChannelResult: Sendable, Hashable, Codable {
    public var criterionID: String?
    public var channelID: String
    public var status: XcircuiteEvaluationStatus
    public var observedValue: XcircuiteJSONValue?
    public var residual: Double?
    public var likelihood: Double?
    public var confidence: XcircuiteEvidenceConfidence?
    public var diagnostics: [XcircuiteRunActionDiagnostic]
    public var metadata: [String: XcircuiteJSONValue]

    public init(
        criterionID: String? = nil,
        channelID: String,
        status: XcircuiteEvaluationStatus,
        observedValue: XcircuiteJSONValue? = nil,
        residual: Double? = nil,
        likelihood: Double? = nil,
        confidence: XcircuiteEvidenceConfidence? = nil,
        diagnostics: [XcircuiteRunActionDiagnostic] = [],
        metadata: [String: XcircuiteJSONValue] = [:]
    ) {
        self.criterionID = criterionID
        self.channelID = channelID
        self.status = status
        self.observedValue = observedValue
        self.residual = residual
        self.likelihood = likelihood
        self.confidence = confidence
        self.diagnostics = diagnostics
        self.metadata = metadata
    }
}

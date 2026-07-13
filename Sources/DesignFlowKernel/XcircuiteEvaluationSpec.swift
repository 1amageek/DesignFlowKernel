import Foundation

public struct XcircuiteEvaluationSpec: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var specID: String
    public var intentID: String?
    public var objective: String
    public var criteria: [XcircuiteEvaluationCriterion]
    public var requiredArtifactRoles: [String]
    public var confidence: XcircuiteEvidenceConfidence?
    public var metadata: [String: XcircuiteJSONValue]

    public init(
        schemaVersion: Int = 1,
        specID: String,
        intentID: String? = nil,
        objective: String,
        criteria: [XcircuiteEvaluationCriterion] = [],
        requiredArtifactRoles: [String] = [],
        confidence: XcircuiteEvidenceConfidence? = nil,
        metadata: [String: XcircuiteJSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.specID = specID
        self.intentID = intentID
        self.objective = objective
        self.criteria = criteria
        self.requiredArtifactRoles = requiredArtifactRoles
        self.confidence = confidence
        self.metadata = metadata
    }
}

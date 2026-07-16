import Foundation

public struct FlowEvaluationSpec: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var specID: String
    public var intentID: String?
    public var objective: String
    public var criteria: [FlowEvaluationCriterion]
    public var requiredArtifactRoles: [String]
    public var confidence: FlowEvidenceConfidence?

    public init(
        schemaVersion: Int = 1,
        specID: String,
        intentID: String? = nil,
        objective: String,
        criteria: [FlowEvaluationCriterion] = [],
        requiredArtifactRoles: [String] = [],
        confidence: FlowEvidenceConfidence? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.specID = specID
        self.intentID = intentID
        self.objective = objective
        self.criteria = criteria
        self.requiredArtifactRoles = requiredArtifactRoles
        self.confidence = confidence
    }
}

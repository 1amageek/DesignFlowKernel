import CircuiteFoundation
import Foundation

public struct FlowRunCrossArtifactEvaluationResult: Sendable, Hashable, Codable {
    public var runID: String
    public var evaluation: FlowCrossArtifactEvaluation
    public var artifactReferences: [ArtifactReference]

    public init(
        runID: String,
        evaluation: FlowCrossArtifactEvaluation,
        artifactReferences: [ArtifactReference] = []
    ) {
        self.runID = runID
        self.evaluation = evaluation
        self.artifactReferences = artifactReferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runID = try container.decode(String.self, forKey: .runID)
        evaluation = try container.decode(FlowCrossArtifactEvaluation.self, forKey: .evaluation)
        artifactReferences = try container.decode([ArtifactReference].self, forKey: .artifactReferences)
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case evaluation
        case artifactReferences
    }
}

import CircuiteFoundation
import Foundation

public struct FlowRunCrossArtifactEvaluationResult: Sendable, Hashable, Codable {
    public var runID: String
    public var evaluation: XcircuiteCrossArtifactEvaluation
    public var artifactReferences: [ArtifactReference]

    public init(
        runID: String,
        evaluation: XcircuiteCrossArtifactEvaluation,
        artifactReferences: [ArtifactReference] = []
    ) {
        self.runID = runID
        self.evaluation = evaluation
        self.artifactReferences = artifactReferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runID = try container.decode(String.self, forKey: .runID)
        evaluation = try container.decode(XcircuiteCrossArtifactEvaluation.self, forKey: .evaluation)
        do {
            artifactReferences = try container.decode([ArtifactReference].self, forKey: .artifactReferences)
        } catch {
            let legacy = try container.decode([XcircuiteFileReference].self, forKey: .artifactReferences)
            artifactReferences = try legacy.map { try $0.foundationArtifactReference() }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case evaluation
        case artifactReferences
    }
}

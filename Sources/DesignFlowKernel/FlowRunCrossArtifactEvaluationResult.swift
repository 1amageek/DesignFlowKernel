import Foundation
import XcircuitePackage

public struct FlowRunCrossArtifactEvaluationResult: Sendable, Hashable, Codable {
    public var runID: String
    public var evaluation: XcircuiteCrossArtifactEvaluation
    public var artifactReferences: [XcircuiteFileReference]

    public init(
        runID: String,
        evaluation: XcircuiteCrossArtifactEvaluation,
        artifactReferences: [XcircuiteFileReference] = []
    ) {
        self.runID = runID
        self.evaluation = evaluation
        self.artifactReferences = artifactReferences
    }
}

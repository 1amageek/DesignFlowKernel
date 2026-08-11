import CircuiteFoundation
import Foundation

/// Immutable evidence reviewed by an approval decision.
public struct FlowApprovalEvidenceBinding: Sendable, Hashable, Codable {
    public var plan: FlowArtifactBinding
    public var stageResult: FlowArtifactBinding
    public var designDiff: FlowArtifactBinding?

    public init(
        plan: FlowArtifactBinding,
        stageResult: FlowArtifactBinding,
        designDiff: FlowArtifactBinding? = nil
    ) {
        self.plan = plan
        self.stageResult = stageResult
        self.designDiff = designDiff
    }
}

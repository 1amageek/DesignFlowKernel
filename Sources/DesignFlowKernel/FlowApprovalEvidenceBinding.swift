import CircuiteFoundation
import Foundation

/// Immutable evidence reviewed by an approval decision.
public struct FlowApprovalEvidenceBinding: Sendable, Hashable, Codable {
    public var plan: ArtifactReference
    public var stageResult: ArtifactReference

    public init(plan: ArtifactReference, stageResult: ArtifactReference) {
        self.plan = plan
        self.stageResult = stageResult
    }
}

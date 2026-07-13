import CircuiteFoundation
import Foundation

public struct FlowRunGuardEvaluationResult: Sendable, Hashable, Codable {
    public var runID: String
    public var profileID: String
    public var snapshot: XcircuiteAgentLoopSnapshot
    public var verdict: XcircuiteRunGuardVerdict
    /// Canonical artifacts produced or consumed while evaluating the guard.
    public var artifactReferences: [ArtifactReference]

    public init(
        runID: String,
        profileID: String,
        snapshot: XcircuiteAgentLoopSnapshot,
        verdict: XcircuiteRunGuardVerdict,
        artifactReferences: [ArtifactReference] = []
    ) {
        self.runID = runID
        self.profileID = profileID
        self.snapshot = snapshot
        self.verdict = verdict
        self.artifactReferences = artifactReferences
    }
}

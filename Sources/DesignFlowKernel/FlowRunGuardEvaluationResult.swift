import Foundation

public struct FlowRunGuardEvaluationResult: Sendable, Hashable, Codable {
    public var runID: String
    public var profileID: String
    public var snapshot: XcircuiteAgentLoopSnapshot
    public var verdict: XcircuiteRunGuardVerdict
    public var artifactReferences: [XcircuiteFileReference]

    public init(
        runID: String,
        profileID: String,
        snapshot: XcircuiteAgentLoopSnapshot,
        verdict: XcircuiteRunGuardVerdict,
        artifactReferences: [XcircuiteFileReference] = []
    ) {
        self.runID = runID
        self.profileID = profileID
        self.snapshot = snapshot
        self.verdict = verdict
        self.artifactReferences = artifactReferences
    }
}


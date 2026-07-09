import Foundation
import XcircuitePackage

public struct FlowRunLoopSummaryResult: Sendable, Hashable, Codable {
    public var runID: String
    public var profileID: String
    public var iterations: [XcircuiteLoopIterationSummary]
    public var snapshot: XcircuiteAgentLoopSnapshot
    public var artifactReferences: [XcircuiteFileReference]

    public init(
        runID: String,
        profileID: String,
        iterations: [XcircuiteLoopIterationSummary],
        snapshot: XcircuiteAgentLoopSnapshot,
        artifactReferences: [XcircuiteFileReference] = []
    ) {
        self.runID = runID
        self.profileID = profileID
        self.iterations = iterations
        self.snapshot = snapshot
        self.artifactReferences = artifactReferences
    }
}


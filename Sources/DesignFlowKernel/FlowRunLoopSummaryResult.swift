import CircuiteFoundation
import Foundation

public struct FlowRunLoopSummaryResult: Sendable, Hashable, Codable {
    public var runID: String
    public var profileID: String
    public var iterations: [FlowLoopIterationSummary]
    public var snapshot: FlowAgentLoopSnapshot
    public var artifactReferences: [ArtifactReference]

    public init(
        runID: String,
        profileID: String,
        iterations: [FlowLoopIterationSummary],
        snapshot: FlowAgentLoopSnapshot,
        artifactReferences: [ArtifactReference] = []
    ) {
        self.runID = runID
        self.profileID = profileID
        self.iterations = iterations
        self.snapshot = snapshot
        self.artifactReferences = artifactReferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runID = try container.decode(String.self, forKey: .runID)
        profileID = try container.decode(String.self, forKey: .profileID)
        iterations = try container.decode([FlowLoopIterationSummary].self, forKey: .iterations)
        snapshot = try container.decode(FlowAgentLoopSnapshot.self, forKey: .snapshot)
        artifactReferences = try container.decode([ArtifactReference].self, forKey: .artifactReferences)
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case profileID
        case iterations
        case snapshot
        case artifactReferences
    }
}

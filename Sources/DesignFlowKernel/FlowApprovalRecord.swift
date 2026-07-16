import Foundation

/// A reviewer decision bound to the exact plan and stage result inspected.
public struct FlowApprovalRecord: Sendable, Hashable, Codable {
    public enum Verdict: String, Sendable, Hashable, Codable {
        case approved
        case waived
        case rejected
    }

    public var runID: String
    public var stageID: String
    public var verdict: Verdict
    public var reviewer: String
    public var reviewerKind: FlowRunActor.Kind
    public var note: String
    public var createdAt: Date
    public var evidence: FlowApprovalEvidenceBinding

    public init(
        runID: String,
        stageID: String,
        verdict: Verdict,
        reviewer: String,
        reviewerKind: FlowRunActor.Kind = .human,
        note: String = "",
        createdAt: Date = Date(),
        evidence: FlowApprovalEvidenceBinding
    ) {
        self.runID = runID
        self.stageID = stageID
        self.verdict = verdict
        self.reviewer = reviewer
        self.reviewerKind = reviewerKind
        self.note = note
        self.createdAt = createdAt
        self.evidence = evidence
    }
}

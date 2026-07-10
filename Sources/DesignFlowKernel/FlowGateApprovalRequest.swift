import Foundation
import XcircuitePackage

public struct FlowGateApprovalRequest: Sendable, Hashable, Codable {
    public var projectRoot: URL
    public var runID: String
    public var stageID: String
    public var verdict: FlowGateApprovalVerdict
    public var reviewer: String
    public var reviewerKind: XcircuiteRunActionActor.Kind
    public var note: String
    public var decidedAt: Date

    public init(
        projectRoot: URL,
        runID: String,
        stageID: String,
        verdict: FlowGateApprovalVerdict,
        reviewer: String,
        reviewerKind: XcircuiteRunActionActor.Kind = .human,
        note: String = "",
        decidedAt: Date = Date()
    ) {
        self.projectRoot = projectRoot
        self.runID = runID
        self.stageID = stageID
        self.verdict = verdict
        self.reviewer = reviewer
        self.reviewerKind = reviewerKind
        self.note = note
        self.decidedAt = decidedAt
    }

    private enum CodingKeys: String, CodingKey {
        case projectRoot
        case runID
        case stageID
        case verdict
        case reviewer
        case reviewerKind
        case note
        case decidedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectRoot = try container.decode(URL.self, forKey: .projectRoot)
        runID = try container.decode(String.self, forKey: .runID)
        stageID = try container.decode(String.self, forKey: .stageID)
        verdict = try container.decode(FlowGateApprovalVerdict.self, forKey: .verdict)
        reviewer = try container.decode(String.self, forKey: .reviewer)
        reviewerKind = try container.decode(
            XcircuiteRunActionActor.Kind.self,
            forKey: .reviewerKind
        )
        note = try container.decode(String.self, forKey: .note)
        decidedAt = try container.decode(Date.self, forKey: .decidedAt)
    }
}

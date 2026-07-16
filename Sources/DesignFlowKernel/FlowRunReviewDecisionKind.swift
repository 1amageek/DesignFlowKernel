import Foundation

public enum FlowRunReviewDecisionKind: String, Sendable, Hashable, Codable, CaseIterable {
    case approval = "review.approvalDecision"
    case waiver = "review.waiverDecision"
    case resume = "review.resumeDecision"
}

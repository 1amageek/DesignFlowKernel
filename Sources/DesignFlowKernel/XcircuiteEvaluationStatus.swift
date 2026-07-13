import Foundation

public enum XcircuiteEvaluationStatus: String, Sendable, Hashable, Codable {
    case accepted
    case rejected
    case inconclusive
    case needsHumanReview
    case blocked
}

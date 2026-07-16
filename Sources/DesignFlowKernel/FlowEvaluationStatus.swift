import Foundation

public enum FlowEvaluationStatus: String, Sendable, Hashable, Codable {
    case accepted
    case rejected
    case inconclusive
    case needsHumanReview
    case blocked
}

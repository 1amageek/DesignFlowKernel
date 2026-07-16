import Foundation

public enum FlowRunActionProjectionError: Error, LocalizedError, Equatable {
    case missingSelectionMetadata(actionID: String, key: String)
    case invalidSelectionMetadata(actionID: String, key: String)
    case missingReviewDecisionMetadata(actionID: String, key: String)
    case invalidReviewDecisionMetadata(actionID: String, key: String)

    public var errorDescription: String? {
        switch self {
        case .missingSelectionMetadata(let actionID, let key):
            "Suggested command selection action \(actionID) is missing metadata key \(key)."
        case .invalidSelectionMetadata(let actionID, let key):
            "Suggested command selection action \(actionID) has invalid metadata for key \(key)."
        case .missingReviewDecisionMetadata(let actionID, let key):
            "Review decision action \(actionID) is missing metadata key \(key)."
        case .invalidReviewDecisionMetadata(let actionID, let key):
            "Review decision action \(actionID) has invalid metadata for key \(key)."
        }
    }
}

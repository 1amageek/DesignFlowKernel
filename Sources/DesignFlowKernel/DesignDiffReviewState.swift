import Foundation

public enum DesignDiffReviewState: String, Sendable, Hashable, Codable {
    case proposed
    case approved
    case rejected
    case applied
    case superseded
}

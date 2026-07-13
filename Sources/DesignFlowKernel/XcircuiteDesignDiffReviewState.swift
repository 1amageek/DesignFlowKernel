import Foundation

public enum XcircuiteDesignDiffReviewState: String, Sendable, Hashable, Codable {
    case proposed
    case approved
    case rejected
    case applied
    case superseded
}

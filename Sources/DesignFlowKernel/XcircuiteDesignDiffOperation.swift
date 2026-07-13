import Foundation

public enum XcircuiteDesignDiffOperation: String, Sendable, Hashable, Codable {
    case add
    case remove
    case replace
    case move
    case copy
    case test
    case metadata
}

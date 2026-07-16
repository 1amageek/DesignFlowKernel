import Foundation

public enum DesignDiffOperation: String, Sendable, Hashable, Codable {
    case add
    case remove
    case replace
    case move
    case copy
    case test
    case metadata
}

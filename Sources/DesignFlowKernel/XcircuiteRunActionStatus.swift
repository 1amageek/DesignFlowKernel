import Foundation

public enum XcircuiteRunActionStatus: String, Sendable, Hashable, Codable {
    case running
    case succeeded
    case failed
    case cancelled
    case blocked
    case partial
}

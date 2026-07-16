import Foundation

public enum FlowRunActionStatus: String, Sendable, Hashable, Codable {
    case running
    case succeeded
    case failed
    case cancelled
    case blocked
    case partial
}

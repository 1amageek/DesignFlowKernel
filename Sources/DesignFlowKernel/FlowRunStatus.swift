import Foundation

public enum FlowRunStatus: String, Sendable, Hashable, Codable {
    case created
    case running
    case succeeded
    case failed
    case blocked
    case cancelled
    case partial
}

import Foundation

public enum XcircuiteRunStatus: String, Sendable, Hashable, Codable {
    case created
    case running
    case succeeded
    case failed
    case cancelled
    case blocked
    case partial

    public var isTerminal: Bool {
        switch self {
        case .created, .running:
            false
        case .succeeded, .failed, .cancelled, .blocked, .partial:
            true
        }
    }

    public func canTransition(to next: XcircuiteRunStatus) -> Bool {
        if self == next {
            return true
        }
        return switch (self, next) {
        case (.created, .running):
            true
        case (.running, .succeeded),
             (.running, .failed),
             (.running, .cancelled),
             (.running, .blocked),
             (.running, .partial):
            true
        case (.failed, .running),
             (.blocked, .running),
             (.blocked, .cancelled):
            true
        default:
            false
        }
    }
}

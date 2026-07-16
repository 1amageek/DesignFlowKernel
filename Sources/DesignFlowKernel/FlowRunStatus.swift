import Foundation

public enum FlowRunStatus: String, Sendable, Hashable, Codable {
    case created
    case running
    case succeeded
    case failed
    case blocked
    case cancelled
    case partial

    public var isTerminal: Bool {
        switch self {
        case .created, .running:
            false
        case .succeeded, .failed, .blocked, .cancelled, .partial:
            true
        }
    }

    public func canTransition(to next: FlowRunStatus) -> Bool {
        if self == next {
            return true
        }
        return switch (self, next) {
        case (.created, .running),
             (.running, .succeeded),
             (.running, .failed),
             (.running, .blocked),
             (.running, .cancelled),
             (.running, .partial),
             (.failed, .running),
             (.blocked, .running),
             (.blocked, .cancelled):
            true
        default:
            false
        }
    }
}

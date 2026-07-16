import Foundation

public enum FlowRunGuardSeverity: String, Sendable, Hashable, Codable, Comparable {
    case info
    case warning
    case error
    case critical

    public static func < (left: FlowRunGuardSeverity, right: FlowRunGuardSeverity) -> Bool {
        left.rank < right.rank
    }

    private var rank: Int {
        switch self {
        case .info:
            0
        case .warning:
            1
        case .error:
            2
        case .critical:
            3
        }
    }
}


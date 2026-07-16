import Foundation

public enum FlowFeedbackSeverity: String, Sendable, Hashable, Codable {
    case info
    case warning
    case error
    case blocker
}

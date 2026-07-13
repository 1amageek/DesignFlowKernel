import Foundation

public enum XcircuiteFeedbackSeverity: String, Sendable, Hashable, Codable {
    case info
    case warning
    case error
    case blocker
}

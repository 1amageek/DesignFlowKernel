import Foundation

public enum FlowStageStatus: String, Sendable, Hashable, Codable {
    case pending
    case running
    case succeeded
    case failed
    case blocked
    case skipped
}

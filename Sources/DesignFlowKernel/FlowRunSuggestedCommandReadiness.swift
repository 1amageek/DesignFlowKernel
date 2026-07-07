import Foundation

public enum FlowRunSuggestedCommandReadiness: String, Sendable, Hashable, Codable {
    case ready
    case requiresInput
}

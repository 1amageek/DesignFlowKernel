import Foundation

public enum FlowRunSuggestedActionReadiness: String, Sendable, Hashable, Codable {
    case ready
    case requiresInput
}

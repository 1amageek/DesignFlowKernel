import Foundation

public enum FlowFeedbackRoutingLevel: String, Sendable, Hashable, Codable {
    case localSurface
    case structureMapping
    case intentDefinition
}

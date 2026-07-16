import Foundation

public enum FlowIdentifierKind: String, Sendable, Hashable, Codable {
    case artifactID
    case projectID
    case runID
    case stageID
    case toolID
}

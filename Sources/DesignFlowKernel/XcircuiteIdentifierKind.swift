import Foundation

public enum XcircuiteIdentifierKind: String, Sendable, Hashable, Codable {
    case artifactID
    case projectID
    case runID
    case stageID
    case toolID
}

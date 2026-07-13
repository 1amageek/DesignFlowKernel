import Foundation

public struct XcircuiteProjectIdentity: Sendable, Hashable, Codable {
    public var projectID: String
    public var displayName: String
    public var topDesignName: String

    public init(projectID: String, displayName: String, topDesignName: String) {
        self.projectID = projectID
        self.displayName = displayName
        self.topDesignName = topDesignName
    }
}

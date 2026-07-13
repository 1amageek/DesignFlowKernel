import Foundation

public struct XcircuiteArtifactDependency: Sendable, Hashable, Codable {
    public var artifactID: String?
    public var path: String
    public var role: String
    public var required: Bool

    public init(
        artifactID: String? = nil,
        path: String,
        role: String,
        required: Bool = true
    ) {
        self.artifactID = artifactID
        self.path = path
        self.role = role
        self.required = required
    }
}

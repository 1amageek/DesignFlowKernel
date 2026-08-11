import CircuiteFoundation
import Foundation

public struct DesignDiffChange: Sendable, Hashable, Codable {
    public var changeID: String
    public var domain: DesignDiffDomain
    public var operation: DesignDiffOperation
    public var path: String
    public var fromPath: String?
    public var before: DesignDiffValue?
    public var after: DesignDiffValue?
    public var artifacts: [FlowArtifactBinding]
    public var summary: String

    public init(
        changeID: String,
        domain: DesignDiffDomain,
        operation: DesignDiffOperation,
        path: String,
        fromPath: String? = nil,
        before: DesignDiffValue? = nil,
        after: DesignDiffValue? = nil,
        artifacts: [FlowArtifactBinding] = [],
        summary: String
    ) {
        self.changeID = changeID
        self.domain = domain
        self.operation = operation
        self.path = path
        self.fromPath = fromPath
        self.before = before
        self.after = after
        self.artifacts = artifacts
        self.summary = summary
    }
}

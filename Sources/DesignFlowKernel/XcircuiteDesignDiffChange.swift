import Foundation

public struct XcircuiteDesignDiffChange: Sendable, Hashable, Codable {
    public var changeID: String
    public var domain: XcircuiteDesignDiffDomain
    public var operation: XcircuiteDesignDiffOperation
    public var path: String
    public var fromPath: String?
    public var before: XcircuiteJSONValue?
    public var after: XcircuiteJSONValue?
    public var artifacts: [XcircuiteFileReference]
    public var summary: String

    public init(
        changeID: String,
        domain: XcircuiteDesignDiffDomain,
        operation: XcircuiteDesignDiffOperation,
        path: String,
        fromPath: String? = nil,
        before: XcircuiteJSONValue? = nil,
        after: XcircuiteJSONValue? = nil,
        artifacts: [XcircuiteFileReference] = [],
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

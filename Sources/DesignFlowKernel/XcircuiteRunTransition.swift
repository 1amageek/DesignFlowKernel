import Foundation

public struct XcircuiteRunTransition: Sendable, Hashable {
    public var status: XcircuiteRunStatus
    public var artifacts: [XcircuiteFileReference]
    public var occurredAt: Date

    public init(
        status: XcircuiteRunStatus,
        artifacts: [XcircuiteFileReference] = [],
        occurredAt: Date = Date()
    ) {
        self.status = status
        self.artifacts = artifacts
        self.occurredAt = occurredAt
    }
}

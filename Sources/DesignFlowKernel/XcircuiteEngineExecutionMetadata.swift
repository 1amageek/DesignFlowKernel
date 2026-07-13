import Foundation

@available(*, deprecated, message: "Use CircuiteFoundation.ExecutionProvenance.")
public struct XcircuiteEngineExecutionMetadata: Sendable, Hashable, Codable {
    public var engineID: String
    public var implementationID: String
    public var implementationVersion: String
    public var startedAt: Date
    public var completedAt: Date
    public var seed: UInt64?

    public init(
        engineID: String,
        implementationID: String,
        implementationVersion: String,
        startedAt: Date,
        completedAt: Date,
        seed: UInt64? = nil
    ) {
        self.engineID = engineID
        self.implementationID = implementationID
        self.implementationVersion = implementationVersion
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.seed = seed
    }
}

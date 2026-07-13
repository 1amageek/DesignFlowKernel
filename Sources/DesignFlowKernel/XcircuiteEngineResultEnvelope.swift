import Foundation

@available(*, deprecated, message: "Use the domain result type and Foundation evidence protocols.")
public struct XcircuiteEngineResultEnvelope<Payload>: Sendable, Hashable, Codable
where Payload: Sendable & Hashable & Codable {
    public var schemaVersion: Int
    public var runID: String
    public var status: XcircuiteEngineExecutionStatus
    public var diagnostics: [XcircuiteEngineDiagnostic]
    public var artifacts: [XcircuiteFileReference]
    public var metadata: XcircuiteEngineExecutionMetadata
    public var payload: Payload

    public init(
        schemaVersion: Int,
        runID: String,
        status: XcircuiteEngineExecutionStatus,
        diagnostics: [XcircuiteEngineDiagnostic] = [],
        artifacts: [XcircuiteFileReference] = [],
        metadata: XcircuiteEngineExecutionMetadata,
        payload: Payload
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.diagnostics = diagnostics
        self.artifacts = artifacts
        self.metadata = metadata
        self.payload = payload
    }
}

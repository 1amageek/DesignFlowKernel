import Foundation

public struct FlowRunCancellationRequest: Sendable, Hashable, Codable {
    @FlowSchemaVersion1 public var schemaVersion: Int
    public var runID: String
    public var requestedBy: String
    public var reason: String
    public var requestedAt: Date

    public init(
        schemaVersion: Int = 1,
        runID: String,
        requestedBy: String,
        reason: String,
        requestedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.requestedBy = requestedBy
        self.reason = reason
        self.requestedAt = requestedAt
    }
}

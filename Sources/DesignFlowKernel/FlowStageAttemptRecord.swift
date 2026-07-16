import Foundation

public struct FlowStageAttemptRecord: Sendable, Hashable, Codable {
    @FlowSchemaVersion1 public var schemaVersion: Int
    public var stageID: String
    public var attemptIndex: Int
    public var maxAttempts: Int
    public var status: FlowStageStatus
    public var diagnosticCodes: [String]
    public var retryDecision: FlowStageRetryDecision
    public var startedAt: Date
    public var finishedAt: Date

    public init(
        schemaVersion: Int = 1,
        stageID: String,
        attemptIndex: Int,
        maxAttempts: Int,
        status: FlowStageStatus,
        diagnosticCodes: [String] = [],
        retryDecision: FlowStageRetryDecision,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.stageID = stageID
        self.attemptIndex = attemptIndex
        self.maxAttempts = maxAttempts
        self.status = status
        self.diagnosticCodes = diagnosticCodes
        self.retryDecision = retryDecision
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

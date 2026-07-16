import Foundation

public struct FlowRunProgressEvent: Sendable, Hashable, Codable {
    @FlowSchemaVersion1 public var schemaVersion: Int
    public var runID: String
    public var sequence: Int
    public var kind: FlowRunProgressEventKind
    public var stageID: String?
    public var stageStatus: FlowStageStatus?
    public var runStatus: FlowRunStatus?
    public var message: String
    public var createdAt: Date

    public init(
        schemaVersion: Int = 1,
        runID: String,
        sequence: Int,
        kind: FlowRunProgressEventKind,
        stageID: String? = nil,
        stageStatus: FlowStageStatus? = nil,
        runStatus: FlowRunStatus? = nil,
        message: String,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.sequence = sequence
        self.kind = kind
        self.stageID = stageID
        self.stageStatus = stageStatus
        self.runStatus = runStatus
        self.message = message
        self.createdAt = createdAt
    }
}

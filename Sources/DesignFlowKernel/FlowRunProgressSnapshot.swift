import Foundation

public struct FlowRunProgressSnapshot: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var afterSequence: Int
    public var latestSequence: Int
    public var events: [FlowRunProgressEvent]
    public var terminalStatus: FlowRunStatus?
    public var isTerminal: Bool
    public var generatedAt: Date

    public init(
        schemaVersion: Int = 1,
        runID: String,
        afterSequence: Int,
        latestSequence: Int,
        events: [FlowRunProgressEvent] = [],
        terminalStatus: FlowRunStatus? = nil,
        generatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.afterSequence = afterSequence
        self.latestSequence = latestSequence
        self.events = events
        self.terminalStatus = terminalStatus
        self.isTerminal = terminalStatus != nil
        self.generatedAt = generatedAt
    }
}

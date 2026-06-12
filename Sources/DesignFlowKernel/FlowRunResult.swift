import Foundation

public struct FlowRunResult: Sendable, Hashable, Codable {
    public var runID: String
    public var status: FlowRunStatus
    public var runDirectory: URL
    public var stages: [FlowStageResult]

    public init(
        runID: String,
        status: FlowRunStatus,
        runDirectory: URL,
        stages: [FlowStageResult]
    ) {
        self.runID = runID
        self.status = status
        self.runDirectory = runDirectory
        self.stages = stages
    }
}

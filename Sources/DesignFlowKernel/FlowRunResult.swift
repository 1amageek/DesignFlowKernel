import Foundation

public struct FlowRunResult: Sendable, Hashable, Codable {
    public var runID: String
    public var status: FlowRunStatus
    public var stages: [FlowStageResult]

    public init(
        runID: String,
        status: FlowRunStatus,
        stages: [FlowStageResult]
    ) {
        self.runID = runID
        self.status = status
        self.stages = stages
    }
}

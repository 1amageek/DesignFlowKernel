import Foundation

public struct FlowRunStageSummary: Sendable, Hashable, Codable {
    public var stageID: String
    public var status: FlowStageStatus
    public var gates: [FlowRunGateSummary]
    public var diagnosticCodes: [String]
    public var artifactCount: Int
    public var attemptCount: Int
    public var retryCount: Int

    public init(
        stageID: String,
        status: FlowStageStatus,
        gates: [FlowRunGateSummary] = [],
        diagnosticCodes: [String] = [],
        artifactCount: Int = 0,
        attemptCount: Int = 0,
        retryCount: Int = 0
    ) {
        self.stageID = stageID
        self.status = status
        self.gates = gates
        self.diagnosticCodes = diagnosticCodes
        self.artifactCount = artifactCount
        self.attemptCount = attemptCount
        self.retryCount = retryCount
    }

}

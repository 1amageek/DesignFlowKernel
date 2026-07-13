import Foundation

public struct FlowStageResult: Sendable, Hashable, Codable {
    public var stageID: String
    public var status: FlowStageStatus
    public var diagnostics: [FlowDiagnostic]
    public var gates: [FlowGateResult]
    public var artifacts: [XcircuiteFileReference]
    public var attempts: [FlowStageAttemptRecord]

    public init(
        stageID: String,
        status: FlowStageStatus,
        diagnostics: [FlowDiagnostic] = [],
        gates: [FlowGateResult] = [],
        artifacts: [XcircuiteFileReference] = [],
        attempts: [FlowStageAttemptRecord] = []
    ) {
        self.stageID = stageID
        self.status = status
        self.diagnostics = diagnostics
        self.gates = gates
        self.artifacts = artifacts
        self.attempts = attempts
    }

}

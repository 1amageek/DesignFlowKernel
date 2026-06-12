import Foundation
import XcircuitePackage

public struct FlowStageResult: Sendable, Hashable, Codable {
    public var stageID: String
    public var status: FlowStageStatus
    public var diagnostics: [FlowDiagnostic]
    public var gates: [FlowGateResult]
    public var artifacts: [XcircuiteFileReference]

    public init(
        stageID: String,
        status: FlowStageStatus,
        diagnostics: [FlowDiagnostic] = [],
        gates: [FlowGateResult] = [],
        artifacts: [XcircuiteFileReference] = []
    ) {
        self.stageID = stageID
        self.status = status
        self.diagnostics = diagnostics
        self.gates = gates
        self.artifacts = artifacts
    }
}

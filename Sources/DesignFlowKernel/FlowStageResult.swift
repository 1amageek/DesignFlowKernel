import Foundation
import XcircuitePackage

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

    private enum CodingKeys: String, CodingKey {
        case stageID
        case status
        case diagnostics
        case gates
        case artifacts
        case attempts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stageID = try container.decode(String.self, forKey: .stageID)
        status = try container.decode(FlowStageStatus.self, forKey: .status)
        diagnostics = try container.decodeIfPresent([FlowDiagnostic].self, forKey: .diagnostics) ?? []
        gates = try container.decodeIfPresent([FlowGateResult].self, forKey: .gates) ?? []
        artifacts = try container.decodeIfPresent([XcircuiteFileReference].self, forKey: .artifacts) ?? []
        attempts = try container.decodeIfPresent([FlowStageAttemptRecord].self, forKey: .attempts) ?? []
    }
}

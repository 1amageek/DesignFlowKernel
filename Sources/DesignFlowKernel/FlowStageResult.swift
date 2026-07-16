import Foundation
import CircuiteFoundation

public struct FlowStageResult: Sendable, Hashable, Codable {
    public var stageID: String
    public var status: FlowStageStatus
    public var diagnostics: [FlowDiagnostic]
    public var gates: [FlowGateResult]
    /// Canonical artifacts emitted by this stage.
    ///
    /// The Foundation reference is the only representation persisted by the
    /// current schema.
    public var artifacts: [ArtifactReference]
    public var attempts: [FlowStageAttemptRecord]

    public init(
        stageID: String,
        status: FlowStageStatus,
        diagnostics: [FlowDiagnostic] = [],
        gates: [FlowGateResult] = [],
        artifacts: [ArtifactReference] = [],
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
        diagnostics = try container.decode([FlowDiagnostic].self, forKey: .diagnostics)
        gates = try container.decode([FlowGateResult].self, forKey: .gates)
        attempts = try container.decode([FlowStageAttemptRecord].self, forKey: .attempts)

        artifacts = try container.decode([ArtifactReference].self, forKey: .artifacts)
    }

}

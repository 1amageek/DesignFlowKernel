import Foundation
import CircuiteFoundation

public struct FlowStageResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var stageID: String
    public var status: FlowStageStatus
    public var diagnostics: [FlowDiagnostic]
    public var gates: [FlowGateResult]
    /// Canonical artifacts emitted by this stage.
    ///
    /// Content identity and materialization are retained as separate values.
    public var artifacts: [FlowArtifactBinding]
    public var attempts: [FlowStageAttemptRecord]

    public init(
        stageID: String,
        status: FlowStageStatus,
        diagnostics: [FlowDiagnostic] = [],
        gates: [FlowGateResult] = [],
        artifacts: [FlowArtifactBinding] = [],
        attempts: [FlowStageAttemptRecord] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.stageID = stageID
        self.status = status
        self.diagnostics = diagnostics
        self.gates = gates
        self.artifacts = artifacts
        self.attempts = attempts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case stageID
        case status
        case diagnostics
        case gates
        case artifacts
        case attempts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected stage result schema version \(Self.currentSchemaVersion)."
            )
        }
        stageID = try container.decode(String.self, forKey: .stageID)
        status = try container.decode(FlowStageStatus.self, forKey: .status)
        diagnostics = try container.decode([FlowDiagnostic].self, forKey: .diagnostics)
        gates = try container.decode([FlowGateResult].self, forKey: .gates)
        attempts = try container.decode([FlowStageAttemptRecord].self, forKey: .attempts)

        artifacts = try container.decode([FlowArtifactBinding].self, forKey: .artifacts)
    }

}

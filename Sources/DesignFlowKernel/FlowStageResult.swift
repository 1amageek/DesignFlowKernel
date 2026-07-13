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
    /// current schema. Legacy Xcircuite references are accepted by the custom
    /// decoder solely to read pre-migration run results.
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

        do {
            artifacts = try container.decode([ArtifactReference].self, forKey: .artifacts)
        } catch {
            // Pre-migration stage results encoded XcircuiteFileReference.
            // Convert only while decoding; all newly encoded results use the
            // Foundation schema above.
            let legacy = try container.decode([XcircuiteFileReference].self, forKey: .artifacts)
            artifacts = try legacy.map { try $0.foundationArtifactReference() }
        }
    }

}

private extension XcircuiteFileKind {
    var foundationRawValue: String {
        switch self {
        case .powerIntent: return "power-intent"
        case .timingLibrary: return "timing-library"
        case .testPattern: return "test-pattern"
        case .ruleDeck: return "rule-deck"
        case .designDiff: return "design-diff"
        case .parasitic: return "parasitics"
        default: return rawValue
        }
    }
}

private extension XcircuiteFileFormat {
    var foundationRawValue: String {
        switch self {
        case .systemVerilog: return "system-verilog"
        default: return rawValue.lowercased()
        }
    }
}

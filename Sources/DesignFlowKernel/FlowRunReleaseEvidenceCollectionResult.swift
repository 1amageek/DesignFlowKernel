import CircuiteFoundation
import Foundation

public struct FlowRunReleaseEvidenceCollectionResult: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var corpusHistory: FlowRunReleaseCorpusHistory
    public var performanceEnvelope: FlowRunReleasePerformanceEnvelope
    public var contractAudit: FlowRunReleaseContractAudit
    /// Canonical Foundation references for all persisted qualification artifacts.
    public var artifacts: [ArtifactReference]
    public var diagnostics: [FlowDiagnostic]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        corpusHistory: FlowRunReleaseCorpusHistory,
        performanceEnvelope: FlowRunReleasePerformanceEnvelope,
        contractAudit: FlowRunReleaseContractAudit,
        artifacts: [ArtifactReference],
        diagnostics: [FlowDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.corpusHistory = corpusHistory
        self.performanceEnvelope = performanceEnvelope
        self.contractAudit = contractAudit
        self.artifacts = artifacts
        self.diagnostics = diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(String.self, forKey: .runID)
        corpusHistory = try container.decode(FlowRunReleaseCorpusHistory.self, forKey: .corpusHistory)
        performanceEnvelope = try container.decode(FlowRunReleasePerformanceEnvelope.self, forKey: .performanceEnvelope)
        contractAudit = try container.decode(FlowRunReleaseContractAudit.self, forKey: .contractAudit)
        do {
            artifacts = try container.decode([ArtifactReference].self, forKey: .artifacts)
        } catch {
            let legacy = try container.decode([XcircuiteFileReference].self, forKey: .artifacts)
            artifacts = try legacy.map { try $0.foundationArtifactReference() }
        }
        diagnostics = try container.decode([FlowDiagnostic].self, forKey: .diagnostics)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case corpusHistory
        case performanceEnvelope
        case contractAudit
        case artifacts
        case diagnostics
    }
}

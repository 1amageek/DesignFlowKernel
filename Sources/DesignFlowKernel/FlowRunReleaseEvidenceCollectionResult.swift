import Foundation
import XcircuitePackage

public struct FlowRunReleaseEvidenceCollectionResult: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var corpusHistory: FlowRunReleaseCorpusHistory
    public var performanceEnvelope: FlowRunReleasePerformanceEnvelope
    public var contractAudit: FlowRunReleaseContractAudit
    public var artifacts: [XcircuiteFileReference]
    public var diagnostics: [FlowDiagnostic]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        corpusHistory: FlowRunReleaseCorpusHistory,
        performanceEnvelope: FlowRunReleasePerformanceEnvelope,
        contractAudit: FlowRunReleaseContractAudit,
        artifacts: [XcircuiteFileReference],
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
}

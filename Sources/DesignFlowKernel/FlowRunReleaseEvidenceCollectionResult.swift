import Foundation
import XcircuitePackage

public struct FlowRunReleaseEvidenceCollectionResult: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var corpusHistory: FlowRunReleaseCorpusHistory
    public var performanceEnvelope: FlowRunReleasePerformanceEnvelope
    public var migrationAudit: FlowRunReleaseMigrationAudit
    public var artifacts: [XcircuiteFileReference]
    public var diagnostics: [FlowDiagnostic]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        corpusHistory: FlowRunReleaseCorpusHistory,
        performanceEnvelope: FlowRunReleasePerformanceEnvelope,
        migrationAudit: FlowRunReleaseMigrationAudit,
        artifacts: [XcircuiteFileReference],
        diagnostics: [FlowDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.corpusHistory = corpusHistory
        self.performanceEnvelope = performanceEnvelope
        self.migrationAudit = migrationAudit
        self.artifacts = artifacts
        self.diagnostics = diagnostics
    }
}

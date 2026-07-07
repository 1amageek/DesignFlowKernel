import Foundation

public protocol FlowRunReleaseEvidenceCollecting: Sendable {
    func collectReleaseEvidence(
        runID: String,
        projectRoot: URL,
        signoffDashboardPath: URL,
        migrationReportPath: URL
    ) throws -> FlowRunReleaseEvidenceCollectionResult
}

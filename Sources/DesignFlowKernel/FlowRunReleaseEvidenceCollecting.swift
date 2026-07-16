import CircuiteFoundation
import Foundation

public protocol FlowRunReleaseEvidenceCollecting: Sendable {
    func collectReleaseEvidence(
        runID: String,
        projectRoot: URL,
        signoffDashboard: ArtifactReference,
        contractReport: ArtifactReference
    ) async throws -> FlowRunReleaseEvidenceCollectionResult
}

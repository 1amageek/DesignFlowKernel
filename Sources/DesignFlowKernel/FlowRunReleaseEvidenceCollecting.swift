import CircuiteFoundation
import Foundation

public protocol FlowRunReleaseEvidenceCollecting: Sendable {
    func collectReleaseEvidence(
        runID: String,
        workspaceID: FlowWorkspaceID,
        signoffDashboard: ArtifactReference,
        contractReport: ArtifactReference
    ) async throws -> FlowRunReleaseEvidenceCollectionResult
}

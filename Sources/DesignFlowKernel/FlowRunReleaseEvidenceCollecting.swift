import CircuiteFoundation
import Foundation

public protocol FlowRunReleaseEvidenceCollecting: Sendable {
    func collectReleaseEvidence(
        runID: String,
        workspaceID: FlowWorkspaceID,
        signoffDashboard: FlowArtifactBinding,
        contractReport: FlowArtifactBinding
    ) async throws -> FlowRunReleaseEvidenceCollectionResult
}

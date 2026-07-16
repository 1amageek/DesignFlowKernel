import CircuiteFoundation
import Foundation

public protocol FlowRunReleaseRetentionIndexBuilding: Sendable {
    func build(
        runID: String,
        workflowRunID: String,
        projectRoot: URL,
        sourceDashboard: ArtifactReference,
        history: ArtifactReference,
        previousEntryCount: Int,
        retentionDays: Int,
        minimumRetentionDays: Int,
        recordedAt: Date
    ) async throws -> FlowRunReleaseRetentionIndex
}

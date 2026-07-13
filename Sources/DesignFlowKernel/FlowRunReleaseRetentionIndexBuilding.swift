import Foundation

public protocol FlowRunReleaseRetentionIndexBuilding: Sendable {
    func build(
        runID: String,
        workflowRunID: String,
        projectRoot: URL,
        sourceDashboardPath: String,
        historyPath: String,
        previousEntryCount: Int,
        retentionDays: Int,
        minimumRetentionDays: Int,
        recordedAt: Date
    ) throws -> FlowRunReleaseRetentionIndex
}

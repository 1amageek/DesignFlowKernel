import Foundation

public protocol FlowRunReleaseRetentionIndexValidating: Sendable {
    func validate(
        index: FlowRunReleaseRetentionIndex,
        runID: String,
        workspaceID: FlowWorkspaceID,
        currentDate: Date,
        maximumAgeSeconds: TimeInterval?
    ) async throws -> FlowRunReleaseRetentionValidationResult
}

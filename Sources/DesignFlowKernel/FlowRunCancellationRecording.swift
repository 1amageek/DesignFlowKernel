import Foundation

public protocol FlowRunCancellationRecording: Sendable {
    func requestCancellation(
        workspaceID: FlowWorkspaceID,
        runID: String,
        requestedBy: String,
        reason: String
    ) async throws -> FlowRunCancellationResult
}

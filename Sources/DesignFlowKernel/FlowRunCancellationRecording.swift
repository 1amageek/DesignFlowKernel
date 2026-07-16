import Foundation

public protocol FlowRunCancellationRecording: Sendable {
    func requestCancellation(
        projectRoot: URL,
        runID: String,
        requestedBy: String,
        reason: String
    ) async throws -> FlowRunCancellationResult
}

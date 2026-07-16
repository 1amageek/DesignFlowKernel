import Foundation

public struct DefaultFlowRunCancellationRecorder: FlowRunCancellationRecording {
    private let progressStore: FlowRunProgressStore

    public init(progressStore: FlowRunProgressStore) {
        self.progressStore = progressStore
    }

    public func requestCancellation(
        workspaceID: FlowWorkspaceID,
        runID: String,
        requestedBy: String,
        reason: String
    ) async throws -> FlowRunCancellationResult {
        let request = try FlowRunCancellationRequest(
            runID: runID,
            requestedBy: requestedBy,
            reason: reason
        )
        let result = try await progressStore.persistCancellationRequest(request)
        _ = try await progressStore.appendEvent(
            runID: runID,
            kind: .cancellationRequested,
            runStatus: .cancelled,
            message: "Cancellation requested by \(requestedBy): \(reason)"
        )
        return result
    }
}

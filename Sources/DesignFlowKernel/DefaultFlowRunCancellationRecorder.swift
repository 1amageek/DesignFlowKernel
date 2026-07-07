import Foundation

public struct DefaultFlowRunCancellationRecorder: FlowRunCancellationRecording {
    private let progressStore: FlowRunProgressStore

    public init(progressStore: FlowRunProgressStore = FlowRunProgressStore()) {
        self.progressStore = progressStore
    }

    public func requestCancellation(
        projectRoot: URL,
        runID: String,
        requestedBy: String,
        reason: String
    ) throws -> FlowRunCancellationResult {
        let request = FlowRunCancellationRequest(
            runID: runID,
            requestedBy: requestedBy,
            reason: reason
        )
        let result = try progressStore.persistCancellationRequest(
            request,
            projectRoot: projectRoot
        )
        _ = try progressStore.appendEvent(
            runID: runID,
            projectRoot: projectRoot,
            kind: .cancellationRequested,
            runStatus: .cancelled,
            message: "Cancellation requested by \(requestedBy): \(reason)"
        )
        return result
    }
}

import CircuiteFoundation
import Foundation

/// Coordinates typed progress records while delegating persistence to the
/// workspace owner.
public struct FlowRunProgressStore: Sendable {
    public static let progressRelativePath = "progress.jsonl"
    public static let cancellationRelativePath = "cancellation.json"

    private let persistence: any FlowRunProgressPersisting

    public init(persistence: any FlowRunProgressPersisting) {
        self.persistence = persistence
    }

    @discardableResult
    public func appendEvent(
        runID: String,
        kind: FlowRunProgressEventKind,
        stageID: String? = nil,
        stageStatus: FlowStageStatus? = nil,
        runStatus: FlowRunStatus? = nil,
        message: String
    ) async throws -> FlowRunProgressEvent {
        let events = try await persistence.loadProgressEvents(
            runID: runID
        )
        let sequence = (events.last?.sequence ?? 0) + 1
        let event = FlowRunProgressEvent(
            runID: runID,
            sequence: sequence,
            kind: kind,
            stageID: stageID,
            stageStatus: stageStatus,
            runStatus: runStatus,
            message: message
        )
        _ = try await persistence.appendProgressEvent(event)
        return event
    }

    public func loadProgressEvents(
        runID: String
    ) async throws -> [FlowRunProgressEvent] {
        try await persistence.loadProgressEvents(runID: runID)
    }

    public func persistCancellationRequest(
        _ request: FlowRunCancellationRequest
    ) async throws -> FlowRunCancellationResult {
        let reference = try await persistence.persistCancellationRequest(
            request
        )
        return FlowRunCancellationResult(
            status: "recorded",
            request: request,
            path: reference.locator.location.value
        )
    }

    public func loadCancellationRequest(
        runID: String
    ) async throws -> FlowRunCancellationRequest? {
        try await persistence.loadCancellationRequest(runID: runID)
    }

    public func runLevelArtifacts(
        runID: String
    ) async throws -> [ArtifactReference] {
        try await persistence.runControlArtifacts(runID: runID)
    }
}

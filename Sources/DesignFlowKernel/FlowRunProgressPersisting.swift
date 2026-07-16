import CircuiteFoundation
import Foundation

/// Persists ordered run progress and cancellation control records.
///
/// Concrete workspace layout, locking, and append semantics belong to the
/// application-level workspace store. The kernel only coordinates typed run
/// records through this boundary.
public protocol FlowRunProgressPersisting: Sendable {
    func appendProgressEvent(
        _ event: FlowRunProgressEvent
    ) async throws -> ArtifactReference

    func loadProgressEvents(
        runID: String
    ) async throws -> [FlowRunProgressEvent]

    func persistCancellationRequest(
        _ request: FlowRunCancellationRequest
    ) async throws -> ArtifactReference

    func loadCancellationRequest(
        runID: String
    ) async throws -> FlowRunCancellationRequest?

    func runControlArtifacts(
        runID: String
    ) async throws -> [ArtifactReference]
}

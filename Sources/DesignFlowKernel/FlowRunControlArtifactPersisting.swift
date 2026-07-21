import CircuiteFoundation
import Foundation

/// Persists artifacts owned by the run lifecycle rather than by a stage
/// executor, such as the run plan and canonical stage-result projections.
public protocol FlowRunControlArtifactPersisting: FlowArtifactPersisting {
    /// Persists an artifact owned by the run lifecycle.
    ///
    /// Concrete storage must keep this path distinct from stage-owned generic
    /// artifact persistence so stage executors cannot overwrite lifecycle
    /// projections such as the plan, result, ledger, or approval records.
    func persistRunControlArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference
}

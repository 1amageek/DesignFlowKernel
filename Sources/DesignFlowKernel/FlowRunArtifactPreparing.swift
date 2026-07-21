import CircuiteFoundation

/// Prepares run-level artifacts that must be retained in terminal evidence.
///
/// Implementations persist their artifacts through their own storage boundary
/// and return canonical references. The orchestrator verifies every reference
/// before adding it to the run evidence set.
public protocol FlowRunArtifactPreparing: Sendable {
    func prepareArtifacts(
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws -> [ArtifactReference]
}

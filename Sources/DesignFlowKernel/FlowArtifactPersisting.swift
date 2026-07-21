import CircuiteFoundation
import Foundation

public protocol FlowArtifactPersisting: Sendable {
    /// Persists content at a storage-relative logical location.
    ///
    /// The persistence implementation owns the concrete filesystem namespace.
    /// Callers must not encode a store-specific root directory in the locator.
    func persistArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference

    /// Persists content while binding the exact producer identity to the
    /// returned artifact reference and durable flow projection.
    func persistArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        producer: ProducerIdentity,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference

    func loadArtifactContent(
        for reference: ArtifactReference
    ) async throws -> Data

    func loadArtifactContent(
        at locator: ArtifactLocator
    ) async throws -> Data?

    func artifactExists(
        at locator: ArtifactLocator
    ) async throws -> Bool

    /// Verifies an artifact through the injected storage boundary without
    /// exposing the storage implementation or filesystem root to the kernel.
    func verifyArtifact(
        _ reference: ArtifactReference
    ) async -> ArtifactIntegrity
}

public extension FlowArtifactPersisting {
    func verifyArtifact(
        _ reference: ArtifactReference
    ) async -> ArtifactIntegrity {
        do {
            _ = try await loadArtifactContent(for: reference)
            return ArtifactIntegrity()
        } catch {
            return ArtifactIntegrity(issues: [.unreadableFile(error.localizedDescription)])
        }
    }
}

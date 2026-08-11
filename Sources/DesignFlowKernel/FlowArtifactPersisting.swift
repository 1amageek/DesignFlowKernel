import CircuiteFoundation
import Foundation

public protocol FlowArtifactPersisting: FlowCandidatePromotionArtifactReading {
    func persistArtifact(
        content: Data,
        logicalID: String,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor,
        runID: String,
        producer: ProducerIdentity?,
        mode: FlowArtifactPersistenceMode
    ) async throws -> FlowArtifactBinding

    func loadArtifactContent(
        at relativePath: ArtifactRelativePath
    ) async throws -> Data?

    func artifactExists(
        at relativePath: ArtifactRelativePath
    ) async throws -> Bool

    /// Verifies an artifact through the injected storage boundary without
    /// exposing the storage implementation or filesystem root to the kernel.
    func verifyArtifact(
        _ artifact: FlowArtifactBinding
    ) async -> ArtifactIntegrity
}

public extension FlowArtifactPersisting {
    func persistArtifact(
        content: Data,
        logicalID: String,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor,
        runID: String,
        mode: FlowArtifactPersistenceMode
    ) async throws -> FlowArtifactBinding {
        try await persistArtifact(
            content: content,
            logicalID: logicalID,
            relativePath: relativePath,
            descriptor: descriptor,
            runID: runID,
            producer: nil,
            mode: mode
        )
    }

    func verifyArtifact(
        _ artifact: FlowArtifactBinding
    ) async -> ArtifactIntegrity {
        do {
            _ = try await loadArtifactContent(for: artifact)
            return ArtifactIntegrity()
        } catch {
            return ArtifactIntegrity(issues: [.unreadableFile(error.localizedDescription)])
        }
    }
}

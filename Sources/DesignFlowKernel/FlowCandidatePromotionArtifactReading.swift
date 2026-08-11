import Foundation

public protocol FlowCandidatePromotionArtifactReading: Sendable {
    func loadArtifactContent(
        for artifact: FlowArtifactBinding
    ) async throws -> Data
}

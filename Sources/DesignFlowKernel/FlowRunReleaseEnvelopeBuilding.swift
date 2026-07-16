import Foundation

public protocol FlowRunReleaseEnvelopeBuilding: Sendable {
    func buildReleaseEnvelope(
        runID: String,
        projectRoot: URL,
        maxEvidenceAgeDays: Int?
    ) async throws -> FlowRunReleaseEnvelopeBuildResult
}

public extension FlowRunReleaseEnvelopeBuilding {
    func buildReleaseEnvelope(
        runID: String,
        projectRoot: URL
    ) async throws -> FlowRunReleaseEnvelopeBuildResult {
        try await buildReleaseEnvelope(
            runID: runID,
            projectRoot: projectRoot,
            maxEvidenceAgeDays: 30
        )
    }
}

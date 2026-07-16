import Foundation

public protocol FlowRunReleaseEnvelopeBuilding: Sendable {
    func buildReleaseEnvelope(
        runID: String,
        workspaceID: FlowWorkspaceID,
        maxEvidenceAgeDays: Int?
    ) async throws -> FlowRunReleaseEnvelopeBuildResult
}

public extension FlowRunReleaseEnvelopeBuilding {
    func buildReleaseEnvelope(
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws -> FlowRunReleaseEnvelopeBuildResult {
        try await buildReleaseEnvelope(
            runID: runID,
            workspaceID: workspaceID,
            maxEvidenceAgeDays: 30
        )
    }
}

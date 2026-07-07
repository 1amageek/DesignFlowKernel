import Foundation

public protocol FlowRunReleaseEnvelopeBuilding: Sendable {
    func buildReleaseEnvelope(
        runID: String,
        projectRoot: URL,
        maxEvidenceAgeDays: Int?
    ) throws -> FlowRunReleaseEnvelopeBuildResult
}

public extension FlowRunReleaseEnvelopeBuilding {
    func buildReleaseEnvelope(
        runID: String,
        projectRoot: URL
    ) throws -> FlowRunReleaseEnvelopeBuildResult {
        try buildReleaseEnvelope(
            runID: runID,
            projectRoot: projectRoot,
            maxEvidenceAgeDays: 30
        )
    }
}

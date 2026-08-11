import CircuiteFoundation
import Foundation

public protocol FlowRunEvidencePersisting: Sendable {
    func loadArtifactEnvelopeRecords(
        runID: String
    ) async throws -> [FlowArtifactEnvelopeRecord]

    func persistCrossArtifactEvaluation(
        _ evaluation: FlowCrossArtifactEvaluation
    ) async throws -> FlowArtifactBinding

    func persistLoopIterationSummaries(
        _ iterations: [FlowLoopIterationSummary],
        runID: String
    ) async throws -> FlowArtifactBinding

    func persistAgentLoopSnapshot(
        _ snapshot: FlowAgentLoopSnapshot
    ) async throws -> FlowArtifactBinding
}

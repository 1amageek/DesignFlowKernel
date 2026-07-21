import Foundation
import CircuiteFoundation

public struct DefaultFlowStageResultValidator: FlowStageResultValidating {
    public init() {}

    public func validate(
        _ result: FlowStageResult,
        expectedStageID: String
    ) throws {
        guard result.stageID == expectedStageID else {
            throw FlowExecutionError.stageResultIdentifierMismatch(
                expected: expectedStageID,
                actual: result.stageID
            )
        }

        let gateIDs = result.gates.map(\.gateID)
        guard Set(gateIDs).count == gateIDs.count else {
            throw FlowExecutionError.invalidStageResult(
                stageID: expectedStageID,
                issue: .duplicateGateIdentifiers
            )
        }

        let hasErrorDiagnostic = (result.diagnostics + result.gates.flatMap(\.diagnostics))
            .contains { $0.severity == .error }
        let hasFailedGate = result.gates.contains { $0.status == .failed }
        let hasBlockingGate = result.gates.contains {
            $0.status == .failed || $0.status == .blocked || $0.status == .incomplete
        }

        switch result.status {
        case .pending, .running:
            throw FlowExecutionError.invalidStageResult(
                stageID: expectedStageID,
                issue: .nonterminalStatus(result.status)
            )
        case .succeeded:
            guard !hasErrorDiagnostic, !hasBlockingGate else {
                throw FlowExecutionError.invalidStageResult(
                    stageID: expectedStageID,
                    issue: .succeededContainsBlockingEvidence
                )
            }
        case .failed:
            guard hasErrorDiagnostic || hasFailedGate else {
                throw FlowExecutionError.invalidStageResult(
                    stageID: expectedStageID,
                    issue: .failedMissingFailureEvidence
                )
            }
        case .blocked:
            guard hasBlockingGate else {
                throw FlowExecutionError.invalidStageResult(
                    stageID: expectedStageID,
                    issue: .blockedMissingBlockingGate
                )
            }
        case .skipped:
            guard !hasErrorDiagnostic, !hasBlockingGate else {
                throw FlowExecutionError.invalidStageResult(
                    stageID: expectedStageID,
                    issue: .skippedContainsBlockingEvidence
                )
            }
        }

        try validateAttempts(
            result.attempts,
            expectedStageID: expectedStageID,
            finalStatus: result.status,
            permitsStatusTransition: result.gates.contains { $0.gateID == "approval" }
        )
        try validateArtifacts(result.artifacts, stageID: expectedStageID)
    }

    private func validateAttempts(
        _ attempts: [FlowStageAttemptRecord],
        expectedStageID: String,
        finalStatus: FlowStageStatus,
        permitsStatusTransition: Bool
    ) throws {
        guard !attempts.isEmpty else { return }
        let expectedIndexes = Array(1 ... attempts.count)
        guard attempts.map(\.attemptIndex) == expectedIndexes else {
            throw FlowExecutionError.invalidStageResult(
                stageID: expectedStageID,
                issue: .noncontiguousAttemptIndexes
            )
        }
        guard attempts.allSatisfy({
            $0.stageID == expectedStageID
                && $0.maxAttempts >= attempts.count
                && $0.attemptIndex <= $0.maxAttempts
                && $0.finishedAt >= $0.startedAt
        }) else {
            throw FlowExecutionError.invalidStageResult(
                stageID: expectedStageID,
                issue: .invalidAttemptMetadata
            )
        }
        guard permitsStatusTransition || attempts.last?.status == finalStatus else {
            throw FlowExecutionError.invalidStageResult(
                stageID: expectedStageID,
                issue: .finalAttemptStatusMismatch(
                    expected: finalStatus,
                    actual: attempts.last?.status
                )
            )
        }
    }

    private func validateArtifacts(
        _ artifacts: [CircuiteFoundation.ArtifactReference],
        stageID: String
    ) throws {
        let identifiers = artifacts.map(\.id)
        let locations = artifacts.map(\.locator.location)
        guard Set(identifiers).count == identifiers.count,
              Set(locations).count == locations.count else {
            throw FlowExecutionError.invalidStageResult(
                stageID: stageID,
                issue: .duplicateArtifactIdentity
            )
        }
    }
}

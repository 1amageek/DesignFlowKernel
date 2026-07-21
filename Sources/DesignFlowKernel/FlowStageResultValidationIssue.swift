import Foundation

public enum FlowStageResultValidationIssue: Sendable, Equatable, LocalizedError {
    case duplicateGateIdentifiers
    case nonterminalStatus(FlowStageStatus)
    case succeededContainsBlockingEvidence
    case failedMissingFailureEvidence
    case blockedMissingBlockingGate
    case skippedContainsBlockingEvidence
    case noncontiguousAttemptIndexes
    case invalidAttemptMetadata
    case finalAttemptStatusMismatch(expected: FlowStageStatus, actual: FlowStageStatus?)
    case duplicateArtifactIdentity

    public var errorDescription: String? {
        switch self {
        case .duplicateGateIdentifiers:
            "Gate identifiers must be unique."
        case .nonterminalStatus(let status):
            "Executor result status must be terminal, got \(status.rawValue)."
        case .succeededContainsBlockingEvidence:
            "A succeeded result cannot contain error diagnostics or blocking gates."
        case .failedMissingFailureEvidence:
            "A failed result requires an error diagnostic or failed gate."
        case .blockedMissingBlockingGate:
            "A blocked result requires a failed, blocked, or incomplete gate."
        case .skippedContainsBlockingEvidence:
            "A skipped result cannot contain error diagnostics or blocking gates."
        case .noncontiguousAttemptIndexes:
            "Attempt indexes must be contiguous and start at one."
        case .invalidAttemptMetadata:
            "Attempt records do not match the stage, time ordering, or retry bounds."
        case .finalAttemptStatusMismatch(let expected, let actual):
            "Final attempt status must be \(expected.rawValue), got \(actual?.rawValue ?? "missing")."
        case .duplicateArtifactIdentity:
            "Artifact identifiers and locations must be unique."
        }
    }
}

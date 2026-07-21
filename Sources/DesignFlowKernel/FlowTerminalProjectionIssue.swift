import Foundation

public enum FlowTerminalProjectionIssue: Sendable, Equatable, LocalizedError {
    case nonterminalStatus(FlowRunStatus)
    case toolchainRunIdentifierMismatch(expected: String, actual: String)
    case duplicateOrMissingStageIdentifiers
    case nonterminalStage(stageID: String, status: FlowStageStatus)
    case invalidStageResult(stageID: String, issue: FlowStageResultValidationIssue)
    case succeededRunContainsUnsuccessfulStage
    case failedRunMissingFailedStage
    case blockedOrCancelledRunMissingBlockedStage
    case invalidPartialRunStages
    case duplicateArtifactLocator
    case evidenceArtifactInventoryMismatch
    case provenanceInputNotRetained
    case stageArtifactNotRetained(stageID: String)
    case toolchainStageInventoryMismatch
    case unexpectedDecisionProjectionMutation

    public var errorDescription: String? {
        switch self {
        case .nonterminalStatus(let status):
            "Run status must be terminal, got \(status.rawValue)."
        case .toolchainRunIdentifierMismatch(let expected, let actual):
            "Toolchain run identifier mismatch: expected \(expected), got \(actual)."
        case .duplicateOrMissingStageIdentifiers:
            "Stage identifiers must be non-empty and unique."
        case .nonterminalStage(let stageID, let status):
            "Terminal run contains nonterminal stage \(stageID) with status \(status.rawValue)."
        case .invalidStageResult(let stageID, let issue):
            "Stage \(stageID) is invalid: \(issue.localizedDescription)"
        case .succeededRunContainsUnsuccessfulStage:
            "A succeeded run can contain only succeeded or skipped stages."
        case .failedRunMissingFailedStage:
            "A failed run requires a failed stage."
        case .blockedOrCancelledRunMissingBlockedStage:
            "A blocked or cancelled run requires a blocked stage."
        case .invalidPartialRunStages:
            "A partial run requires skipped stages and cannot contain failed or blocked stages."
        case .duplicateArtifactLocator:
            "Artifact locators must be unique. A physical location may be referenced under distinct handoff roles."
        case .evidenceArtifactInventoryMismatch:
            "Evidence artifacts must exactly match the ledger artifact inventory."
        case .provenanceInputNotRetained:
            "Every provenance input must be retained in the artifact inventory."
        case .stageArtifactNotRetained(let stageID):
            "Stage \(stageID) references an artifact outside the retained inventory."
        case .toolchainStageInventoryMismatch:
            "Toolchain stage identifiers must be unique and exactly match stage results."
        case .unexpectedDecisionProjectionMutation:
            "Only canonical approval and action projections may change persisted terminal evidence."
        }
    }
}

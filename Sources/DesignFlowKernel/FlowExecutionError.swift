import Foundation

public enum FlowExecutionError: Error, LocalizedError, Equatable {
    case missingExecutor(String)
    case duplicateStageID(String)
    case duplicateExecutorStageID(String)
    case invalidExecutorToolID(stageID: String, toolID: String)
    case invalidRetryPolicy(stageID: String, maxAttempts: Int)
    case duplicateRunID(String)
    case existingRunPlanMismatch(String)
    case missingArtifact(String)
    case invalidRunArtifactReference(artifactID: String, reason: String)
    case conflictingArtifactReference(artifactID: String, location: String)
    case stageResultIdentifierMismatch(expected: String, actual: String)
    case invalidStageResult(stageID: String, issue: FlowStageResultValidationIssue)
    case setupFailureTerminalizationFailed(
        setup: FlowFailureContext,
        terminalization: FlowFailureContext
    )
    case executionFailureTerminalizationFailed(
        execution: FlowFailureContext,
        terminalization: FlowFailureContext
    )
    case artifactIntegrityFailure(
        stageID: String,
        artifactID: String,
        artifactPath: String,
        issues: [String]
    )
    case runArtifactIntegrityFailure(artifactID: String, issues: [String])

    public var errorDescription: String? {
        switch self {
        case .missingExecutor(let stageID):
            "Missing flow stage executor: \(stageID)"
        case .duplicateStageID(let stageID):
            "Duplicate flow stage ID: \(stageID)"
        case .duplicateExecutorStageID(let stageID):
            "Duplicate flow stage executor ID: \(stageID)"
        case .invalidExecutorToolID(let stageID, let toolID):
            "Invalid executor tool ID for stage \(stageID): \(toolID)"
        case .invalidRetryPolicy(let stageID, let maxAttempts):
            "Invalid retry policy for stage \(stageID): maxAttempts must be at least 1, got \(maxAttempts)"
        case .duplicateRunID(let runID):
            "Run directory already exists for run ID: \(runID)"
        case .existingRunPlanMismatch(let runID):
            "Existing run plan does not match the requested run: \(runID)"
        case .missingArtifact(let path):
            "Required run artifact is missing: \(path)"
        case .invalidRunArtifactReference(let artifactID, let reason):
            "Run artifact reference \(artifactID) is invalid: \(reason)"
        case .conflictingArtifactReference(let artifactID, let location):
            "Artifact \(artifactID) has conflicting references at \(location)"
        case .stageResultIdentifierMismatch(let expected, let actual):
            "Stage result identifier mismatch: expected \(expected), got \(actual)"
        case .invalidStageResult(let stageID, let issue):
            "Invalid stage result for \(stageID): \(issue.localizedDescription)"
        case .setupFailureTerminalizationFailed(let setup, let terminalization):
            "Run setup failed with \(setup.errorType): \(setup.message). Failure finalization also failed with \(terminalization.errorType): \(terminalization.message)"
        case .executionFailureTerminalizationFailed(let execution, let terminalization):
            "Run execution failed with \(execution.errorType): \(execution.message). Failure finalization also failed with \(terminalization.errorType): \(terminalization.message)"
        case .artifactIntegrityFailure(let stageID, let artifactID, let artifactPath, let issues):
            "Artifact integrity failure for stage \(stageID), artifact \(artifactID) at \(artifactPath): \(issues.joined(separator: ", "))"
        case .runArtifactIntegrityFailure(let artifactID, let issues):
            "Run artifact integrity failure for artifact \(artifactID): \(issues.joined(separator: ", "))"
        }
    }
}

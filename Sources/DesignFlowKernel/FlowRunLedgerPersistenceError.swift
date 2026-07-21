import Foundation

public enum FlowRunLedgerPersistenceError: Error, Sendable, Equatable, LocalizedError {
    case invalidTransition(runID: String, from: String, to: String)
    case resumeTargetNotFound(runID: String)
    case runAlreadyExists(runID: String)
    case runIdentifierMismatch(requested: String, stored: String)
    case invalidInitialProjection(runID: String, issue: FlowInitialProjectionIssue)
    case protectedProjectionMutation(runID: String, field: String)
    case invalidTerminalProjection(runID: String, issue: FlowTerminalProjectionIssue)
    case invalidEvidenceProjection(runID: String, issue: FlowTerminalProjectionIssue)
    case concurrentUpdate(runID: String, expectedRevision: Int, actualRevision: Int)
    case artifactReferenceMutation(runID: String, path: String)
    case artifactIntegrityFailure(path: String, reason: String)
    case duplicateActionID(runID: String, actionID: String)
    case duplicateApprovalID(runID: String, approvalID: String)
    case actionArtifactBindingMismatch(runID: String, path: String)
    case encodingFailed(String)
    case decodingFailed(String)
    case storageFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let runID, let from, let to):
            "Invalid run transition for \(runID): \(from) -> \(to)"
        case .resumeTargetNotFound(let runID):
            "Resume target run was not found: \(runID)"
        case .runAlreadyExists(let runID):
            "Run ledger already exists: \(runID)"
        case .runIdentifierMismatch(let requested, let stored):
            "Loaded run ledger identifier does not match the requested run: requested \(requested), stored \(stored)"
        case .invalidInitialProjection(let runID, let issue):
            "Invalid initial run projection for \(runID): \(issue.localizedDescription)"
        case .protectedProjectionMutation(let runID, let field):
            "Run ledger update for \(runID) attempted to mutate kernel-owned projection '\(field)'"
        case .invalidTerminalProjection(let runID, let issue):
            "Invalid terminal run projection for \(runID): \(issue.localizedDescription)"
        case .invalidEvidenceProjection(let runID, let issue):
            "Invalid evidence projection for \(runID): \(issue.localizedDescription)"
        case .concurrentUpdate(let runID, let expectedRevision, let actualRevision):
            "Concurrent run-ledger update for \(runID): expected revision \(expectedRevision), found \(actualRevision)"
        case .artifactReferenceMutation(let runID, let path):
            "Run \(runID) attempted to remove or mutate the identity, digest, size, or producer of retained artifact \(path)."
        case .artifactIntegrityFailure(let path, let reason):
            "Run artifact integrity failure at \(path): \(reason)"
        case .duplicateActionID(let runID, let actionID):
            "Run \(runID) already contains action \(actionID)."
        case .duplicateApprovalID(let runID, let approvalID):
            "Run \(runID) already contains approval \(approvalID)."
        case .actionArtifactBindingMismatch(let runID, let path):
            "Run action artifact at \(path) is not exactly bound to run \(runID)."
        case .encodingFailed(let message):
            "Run ledger encoding failed: \(message)"
        case .decodingFailed(let message):
            "Run ledger decoding failed: \(message)"
        case .storageFailed(let message):
            "Run ledger storage failed: \(message)"
        }
    }
}

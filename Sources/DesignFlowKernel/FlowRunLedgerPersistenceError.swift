import Foundation

public enum FlowRunLedgerPersistenceError: Error, Sendable, Equatable, LocalizedError {
    case invalidTransition(runID: String, from: String, to: String)
    case resumeTargetNotFound(runID: String)
    case runIdentifierMismatch(requested: String, stored: String)
    case artifactIntegrityFailure(path: String, reason: String)
    case encodingFailed(String)
    case decodingFailed(String)
    case storageFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let runID, let from, let to):
            "Invalid run transition for \(runID): \(from) -> \(to)"
        case .resumeTargetNotFound(let runID):
            "Resume target run was not found: \(runID)"
        case .runIdentifierMismatch(let requested, let stored):
            "Loaded run ledger identifier does not match the requested run: requested \(requested), stored \(stored)"
        case .artifactIntegrityFailure(let path, let reason):
            "Run artifact integrity failure at \(path): \(reason)"
        case .encodingFailed(let message):
            "Run ledger encoding failed: \(message)"
        case .decodingFailed(let message):
            "Run ledger decoding failed: \(message)"
        case .storageFailed(let message):
            "Run ledger storage failed: \(message)"
        }
    }
}

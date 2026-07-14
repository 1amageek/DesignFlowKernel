import Foundation

public enum FlowRunCrossArtifactEvaluationError: Error, Equatable, Sendable, LocalizedError {
    case evidenceDirectoryReadFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .evidenceDirectoryReadFailed(let path, let reason):
            "Unable to read cross-artifact evidence directory '\(path)': \(reason)"
        }
    }
}

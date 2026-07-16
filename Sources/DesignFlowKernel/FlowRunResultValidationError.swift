import Foundation

public enum FlowRunResultValidationError: Error, LocalizedError, Sendable, Equatable {
    case artifactEvidenceMismatch
    case diagnosticEvidenceMismatch

    public var errorDescription: String? {
        switch self {
        case .artifactEvidenceMismatch:
            "Flow result evidence does not match the artifacts emitted by its stages."
        case .diagnosticEvidenceMismatch:
            "Flow result diagnostics do not match the diagnostics emitted by its stages."
        }
    }
}

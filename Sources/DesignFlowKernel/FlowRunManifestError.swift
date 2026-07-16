import Foundation

public enum FlowRunManifestError: Error, Sendable, Equatable, LocalizedError {
    case invalidManifest(runID: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest(let runID, let reason):
            return "Invalid run manifest for \(runID): \(reason)"
        }
    }
}

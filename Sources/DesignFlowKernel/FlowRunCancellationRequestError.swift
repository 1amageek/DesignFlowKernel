import Foundation

public enum FlowRunCancellationRequestError: Error, LocalizedError, Sendable, Equatable {
    case invalidSchemaVersion(Int)
    case emptyRequestedBy
    case emptyReason

    public var errorDescription: String? {
        switch self {
        case .invalidSchemaVersion(let version):
            "Unsupported cancellation request schema version: \(version)."
        case .emptyRequestedBy:
            "Cancellation requestedBy must not be empty."
        case .emptyReason:
            "Cancellation reason must not be empty."
        }
    }
}

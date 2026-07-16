import Foundation

public enum FlowRunReleaseEvidenceCollectionError: Error, Equatable, LocalizedError {
    case invalidSourceField(source: String, fieldPath: String, expected: String, actual: String)
    case sourceReadFailed(source: String, reason: String)
    case sourceDecodeFailed(source: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidSourceField(let source, let fieldPath, let expected, let actual):
            "\(source) field '\(fieldPath)' expected \(expected), got \(actual)."
        case .sourceReadFailed(let source, let reason):
            "Failed to read \(source): \(reason)"
        case .sourceDecodeFailed(let source, let reason):
            "Failed to decode \(source): \(reason)"
        }
    }
}

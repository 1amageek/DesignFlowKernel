import Foundation

public enum FlowRunReleaseEvidenceCollectionError: Error, Equatable, LocalizedError {
    case invalidSourceField(source: String, fieldPath: String, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidSourceField(let source, let fieldPath, let expected, let actual):
            "\(source) field '\(fieldPath)' expected \(expected), got \(actual)."
        }
    }
}

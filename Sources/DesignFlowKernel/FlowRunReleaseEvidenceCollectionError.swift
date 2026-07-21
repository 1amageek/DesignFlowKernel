import CircuiteFoundation
import Foundation

public enum FlowRunReleaseEvidenceCollectionError: Error, Equatable, LocalizedError {
    case invalidSourceField(source: String, fieldPath: String, expected: String, actual: String)
    case persistedProducerMismatch(
        artifactID: String,
        expected: ProducerIdentity,
        actual: ProducerIdentity?
    )
    case sourceReadFailed(source: String, reason: String)
    case sourceDecodeFailed(source: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidSourceField(let source, let fieldPath, let expected, let actual):
            "\(source) field '\(fieldPath)' expected \(expected), got \(actual)."
        case .persistedProducerMismatch(let artifactID, let expected, let actual):
            "Persisted release evidence \(artifactID) producer mismatch: expected \(Self.describe(expected)), got \(Self.describe(actual))."
        case .sourceReadFailed(let source, let reason):
            "Failed to read \(source): \(reason)"
        case .sourceDecodeFailed(let source, let reason):
            "Failed to decode \(source): \(reason)"
        }
    }

    private static func describe(_ producer: ProducerIdentity) -> String {
        "\(producer.kind.rawValue):\(producer.identifier)@\(producer.version)"
    }

    private static func describe(_ producer: ProducerIdentity?) -> String {
        guard let producer else {
            return "missing"
        }
        return describe(producer)
    }
}

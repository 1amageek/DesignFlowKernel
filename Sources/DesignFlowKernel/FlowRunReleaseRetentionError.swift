import Foundation

public enum FlowRunReleaseRetentionError: Error, LocalizedError, Equatable {
    case invalidHistoryEncoding
    case missingSourceArtifact(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHistoryEncoding:
            "Retention history is not UTF-8 JSONL."
        case .missingSourceArtifact(let path):
            "Retention source artifact is missing: \(path)"
        }
    }
}

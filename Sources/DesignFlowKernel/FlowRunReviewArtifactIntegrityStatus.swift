import Foundation

public enum FlowRunReviewArtifactIntegrityStatus: String, Sendable, Hashable, Codable {
    case verified
    case missingArtifact
    case missingDigest
    case missingByteCount
    case invalidDigest
    case invalidByteCount
    case byteCountMismatch
    case sha256Mismatch
    case invalidIdentifier
    case noRecordedReference
    case invalidPath
    case unreadableArtifact
}

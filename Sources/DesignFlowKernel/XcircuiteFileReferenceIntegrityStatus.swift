import Foundation

public enum XcircuiteFileReferenceIntegrityStatus: String, Sendable, Hashable, Codable {
    case verified
    case missingArtifact
    case missingDigest
    case missingByteCount
    case invalidDigest
    case invalidByteCount
    case byteCountMismatch
    case sha256Mismatch
    case invalidPath
    case unreadableArtifact
}

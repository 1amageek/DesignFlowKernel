import Foundation

public enum XcircuitePackageError: Error, LocalizedError, Equatable {
    case createDirectoryFailed(String)
    case encodeFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case decodeFailed(String)
    case invalidIdentifier(kind: String, value: String)
    case invalidProjectManifest(String)
    case runDirectoryAlreadyExists(String)
    case runReferenceNotFound(String)
    case runManifestProjectionMissing(String)
    case runManifestProjectionMismatch(runID: String, reason: String)
    case runIdentityMismatch(expected: String, actual: String)
    case invalidRunManifest(runID: String, reason: String)
    case invalidRunTransition(runID: String, from: XcircuiteRunStatus, to: XcircuiteRunStatus)
    case runManifestCannotBeProjectFile(String)
    case fileLockFailed(String)
    case unsafeProjectPath(String)

    public var errorDescription: String? {
        switch self {
        case .createDirectoryFailed(let message):
            "Failed to create directory: \(message)"
        case .encodeFailed(let message):
            "Failed to encode package data: \(message)"
        case .writeFailed(let message):
            "Failed to write package data: \(message)"
        case .readFailed(let message):
            "Failed to read package data: \(message)"
        case .decodeFailed(let message):
            "Failed to decode package data: \(message)"
        case .invalidIdentifier(let kind, let value):
            "Invalid \(kind): \(value). Use only letters, numbers, '.', '_', or '-', and do not use '.' or '..'."
        case .invalidProjectManifest(let reason):
            "Invalid project manifest: \(reason)"
        case .runDirectoryAlreadyExists(let runID):
            "Run directory already exists for \(runID). Use ensureRunDirectory for resume or artifact append paths."
        case .runReferenceNotFound(let runID):
            "Project ledger has no run reference for \(runID)."
        case .runManifestProjectionMissing(let runID):
            "Project ledger has no integrity projection for the canonical manifest of \(runID)."
        case .runManifestProjectionMismatch(let runID, let reason):
            "Run manifest projection mismatch for \(runID): \(reason)"
        case .runIdentityMismatch(let expected, let actual):
            "Run manifest identity mismatch: expected \(expected), found \(actual)."
        case .invalidRunManifest(let runID, let reason):
            "Invalid run manifest for \(runID): \(reason)"
        case .invalidRunTransition(let runID, let current, let next):
            "Invalid run lifecycle transition for \(runID): \(current.rawValue) -> \(next.rawValue)."
        case .runManifestCannotBeProjectFile(let path):
            "Run manifest integrity projection cannot be registered directly: \(path). Mutate the run through XcircuiteRunLedgerStoring so the projection is synchronized automatically."
        case .fileLockFailed(let message):
            "Failed to lock package data: \(message)"
        case .unsafeProjectPath(let path):
            "Unsafe project path: \(path). Use a non-empty project-relative path without '~', absolute paths, or '..'."
        }
    }
}

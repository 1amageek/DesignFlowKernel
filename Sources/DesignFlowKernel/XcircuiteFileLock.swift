import Darwin
import Foundation

struct XcircuiteFileLock {
    static func withExclusiveLock<Value>(
        at lockURL: URL,
        _ operation: () throws -> Value
    ) throws -> Value {
        try withLock(at: lockURL, operation: LOCK_EX, body: operation)
    }

    static func withSharedLock<Value>(
        at lockURL: URL,
        _ operation: () throws -> Value
    ) throws -> Value {
        try withLock(at: lockURL, operation: LOCK_SH, body: operation)
    }

    private static func withLock<Value>(
        at lockURL: URL,
        operation: Int32,
        body: () throws -> Value
    ) throws -> Value {
        let descriptor = open(
            lockURL.path(percentEncoded: false),
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw XcircuitePackageError.fileLockFailed(systemError(for: lockURL))
        }
        guard flock(descriptor, operation) == 0 else {
            let message = systemError(for: lockURL)
            _ = close(descriptor)
            throw XcircuitePackageError.fileLockFailed(message)
        }

        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = close(descriptor)
        }
        return try body()
    }

    private static func systemError(for lockURL: URL) -> String {
        let message = String(cString: strerror(errno))
        return "\(lockURL.lastPathComponent): \(message)"
    }
}

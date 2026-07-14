import CryptoKit
import Foundation

public struct XcircuiteHasher: Sendable {
    public init() {}

    public func sha256(data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public func sha256(fileAt url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XcircuitePackageError.readFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
        return sha256(data: data)
    }

    public func byteCount(fileAt url: URL) throws -> Int64 {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(
                atPath: url.path(percentEncoded: false)
            )
        } catch {
            throw XcircuitePackageError.readFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }

        guard let size = attributes[.size] as? NSNumber else {
            throw XcircuitePackageError.readFailed(
                "\(url.lastPathComponent): file size is unavailable"
            )
        }
        return size.int64Value
    }
}

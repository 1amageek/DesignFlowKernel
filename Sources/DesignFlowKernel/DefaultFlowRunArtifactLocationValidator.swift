import CircuiteFoundation
import Foundation

public struct DefaultFlowRunArtifactLocationValidator: FlowRunArtifactLocationValidator {
    private let storagePrefix: String?

    public init(storagePrefix: String? = nil) {
        let normalized = storagePrefix?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.storagePrefix = normalized?.isEmpty == false ? normalized : nil
    }

    public func relativePath(boundTo logicalPath: String) throws -> ArtifactRelativePath {
        let path = storagePrefix.map { "\($0)/\(logicalPath)" } ?? logicalPath
        return try FlowArtifactPath.relative(path)
    }

    public func isBinding(
        _ binding: FlowArtifactBinding,
        boundTo logicalPath: String,
        allowingContentAddressedVariant: Bool
    ) -> Bool {
        guard case .local(_, _, let relativePath) = binding.availability else {
            return false
        }
        let expectedPath = storagePrefix.map { "\($0)/\(logicalPath)" } ?? logicalPath
        if relativePath.stringValue == expectedPath {
            return true
        }
        guard allowingContentAddressedVariant else {
            return false
        }
        return relativePath.stringValue == contentAddressedPath(
            for: expectedPath,
            digest: binding.reference.digest
        )
    }

    private func contentAddressedPath(
        for path: String,
        digest: ContentDigest
    ) -> String {
        let pathExtension = (path as NSString).pathExtension
        let basePath = pathExtension.isEmpty
            ? path
            : String(path.dropLast(pathExtension.count + 1))
        return "\(basePath)-\(digest.algorithm.rawValue)-\(digest.hexadecimalValue)"
            + (pathExtension.isEmpty ? "" : ".\(pathExtension)")
    }
}

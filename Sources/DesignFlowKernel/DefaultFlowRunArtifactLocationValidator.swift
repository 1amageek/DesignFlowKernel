import CircuiteFoundation
import Foundation

public struct DefaultFlowRunArtifactLocationValidator: FlowRunArtifactLocationValidator {
    private let storagePrefix: String?

    public init(storagePrefix: String? = nil) {
        let normalized = storagePrefix?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.storagePrefix = normalized?.isEmpty == false ? normalized : nil
    }

    public func location(boundTo logicalPath: String) throws -> ArtifactLocation {
        let path = storagePrefix.map { "\($0)/\(logicalPath)" } ?? logicalPath
        return try ArtifactLocation(workspaceRelativePath: path)
    }

    public func isReference(
        _ reference: ArtifactReference,
        boundTo logicalPath: String,
        allowingContentAddressedVariant: Bool
    ) -> Bool {
        guard reference.locator.location.storage == .workspaceRelative else {
            return false
        }
        let expectedPath = storagePrefix.map { "\($0)/\(logicalPath)" } ?? logicalPath
        if reference.path == expectedPath {
            return true
        }
        guard allowingContentAddressedVariant else {
            return false
        }
        return reference.path == contentAddressedPath(
            for: expectedPath,
            digest: reference.digest
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

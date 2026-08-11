import CircuiteFoundation

public protocol FlowRunArtifactLocationValidator: Sendable {
    func relativePath(boundTo logicalPath: String) throws -> ArtifactRelativePath

    func isBinding(
        _ binding: FlowArtifactBinding,
        boundTo logicalPath: String,
        allowingContentAddressedVariant: Bool
    ) -> Bool
}

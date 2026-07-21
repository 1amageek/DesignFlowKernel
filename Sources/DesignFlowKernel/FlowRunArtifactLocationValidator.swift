import CircuiteFoundation

public protocol FlowRunArtifactLocationValidator: Sendable {
    func location(boundTo logicalPath: String) throws -> ArtifactLocation

    func isReference(
        _ reference: ArtifactReference,
        boundTo logicalPath: String,
        allowingContentAddressedVariant: Bool
    ) -> Bool
}

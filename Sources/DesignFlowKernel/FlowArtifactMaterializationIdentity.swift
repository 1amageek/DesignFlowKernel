import CircuiteFoundation

enum FlowArtifactMaterializationIdentity: Sendable, Hashable {
    case local(rootID: ArtifactRootID, relativePath: ArtifactRelativePath)
    case service(resource: ArtifactResourceReference)

    init(_ availability: ArtifactAvailability) {
        switch availability {
        case .local(_, let rootID, let relativePath):
            self = .local(rootID: rootID, relativePath: relativePath)
        case .service(_, let resource):
            self = .service(resource: resource)
        }
    }
}

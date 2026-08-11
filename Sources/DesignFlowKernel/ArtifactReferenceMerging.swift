import CircuiteFoundation

func mergedArtifactBindings(
    _ artifacts: [FlowArtifactBinding]
) throws -> [FlowArtifactBinding] {
    var contentByMaterialization: [FlowArtifactMaterializationIdentity: ArtifactID] = [:]
    var uniqueBindings: Set<FlowArtifactBinding> = []
    for artifact in artifacts {
        let identity = FlowArtifactMaterializationIdentity(artifact.availability)
        if let existingContent = contentByMaterialization[identity] {
            guard existingContent == artifact.reference.id else {
                throw FlowExecutionError.conflictingArtifactReference(
                    artifactID: artifact.logicalID,
                    location: artifact.availabilityDescription
                )
            }
        } else {
            contentByMaterialization[identity] = artifact.reference.id
        }
        uniqueBindings.insert(artifact)
    }
    return uniqueBindings.sorted { lhs, rhs in
        if lhs.availabilityDescription != rhs.availabilityDescription {
            return lhs.availabilityDescription < rhs.availabilityDescription
        }
        return lhs.logicalID < rhs.logicalID
    }
}

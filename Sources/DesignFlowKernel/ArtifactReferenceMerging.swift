import CircuiteFoundation

func mergedArtifactBindings(
    _ artifacts: [FlowArtifactBinding]
) throws -> [FlowArtifactBinding] {
    var bindingByMaterialization: [FlowArtifactMaterializationIdentity: FlowArtifactBinding] = [:]
    var uniqueBindings: Set<FlowArtifactBinding> = []
    for artifact in artifacts {
        let identity = FlowArtifactMaterializationIdentity(artifact.availability)
        if let existing = bindingByMaterialization[identity] {
            guard existing.reference.id == artifact.reference.id,
                  existing.producer == artifact.producer else {
                throw FlowExecutionError.conflictingArtifactReference(
                    artifactID: artifact.logicalID,
                    location: artifact.availabilityDescription
                )
            }
        } else {
            bindingByMaterialization[identity] = artifact
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

import CircuiteFoundation

func mergedArtifactReferences(
    _ artifacts: [ArtifactReference]
) throws -> [ArtifactReference] {
    var referencesByLocator: [ArtifactLocator: ArtifactReference] = [:]
    for artifact in artifacts {
        if let existing = referencesByLocator[artifact.locator] {
            guard existing == artifact else {
                throw FlowExecutionError.conflictingArtifactReference(
                    artifactID: artifact.id.rawValue,
                    location: artifact.locator.location.value
                )
            }
            continue
        }
        referencesByLocator[artifact.locator] = artifact
    }
    return referencesByLocator.values.sorted { lhs, rhs in
        if lhs.locator.location.value != rhs.locator.location.value {
            return lhs.locator.location.value < rhs.locator.location.value
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }
}

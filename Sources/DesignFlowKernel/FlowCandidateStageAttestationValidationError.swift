import CircuiteFoundation

public enum FlowCandidateStageAttestationValidationError: Error, Sendable, Hashable {
    case unsupportedSchemaVersion(Int)
    case emptyField(String)
    case duplicateRawEvidence(ArtifactID)
    case resultRepeatedAsRawEvidence(ArtifactID)
    case duplicateInputArtifact(ArtifactID)
    case inputOutputOverlap(ArtifactID)
    case attestationDigestMismatch(expected: ContentDigest, actual: ContentDigest)
    case attestationDigestComputationFailed(String)
}

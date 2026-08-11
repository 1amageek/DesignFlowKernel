import CircuiteFoundation

public enum FlowCandidatePromotionAuthorizationValidationError:
    Error,
    Sendable,
    Hashable
{
    case decisionInvalid(String)
    case authorizationDigestMismatch(expected: ContentDigest, actual: ContentDigest)
    case authorizationDigestComputationFailed(String)
    case decisionNotAuthorized
    case decisionRunIDMismatch
    case decisionApprovalArtifactsMismatch
    case decisionIdentityMismatch
    case candidateRevisionMismatch
    case databaseMismatch
    case semanticGraphDigestMismatch
    case evidenceBindingDigestMismatch
    case designDiffArtifactMismatch
    case targetReferenceMismatch
    case expectedReferenceStateMismatch
    case authorizationNotYetValid
    case authorizationExpired
}

import CircuiteFoundation

public enum FlowCandidatePromotionDecisionValidationError:
    Error, Sendable, Hashable {
    case emptyField(String)
    case duplicateReasonCode(String)
    case duplicateApproval(ArtifactID)
    case authorizedWithoutApproval
    case decisionDigestMismatch(expected: ContentDigest, actual: ContentDigest)
    case decisionDigestComputationFailed(String)
}

import CircuiteFoundation
import Foundation

public enum DefaultFlowCandidatePromotionAuthorizerError:
    Error, Sendable, Hashable {
    case emptyTargetReferenceName
    case evidenceInvalid(String)
    case unsuccessfulRetainedStage(String)
    case duplicateApprovalArtifact(ArtifactID)
    case artifactBudgetExceeded(logicalID: String, actual: UInt64, maximum: UInt64)
    case artifactReadFailed(logicalID: String, reason: String)
    case artifactSizeMismatch(logicalID: String, expected: UInt64, actual: UInt64)
    case artifactDigestMismatch(logicalID: String)
    case artifactDigestComputationFailed(logicalID: String, reason: String)
    case artifactDecodeFailed(logicalID: String, reason: String)
    case evidenceArtifactMismatch
    case designDiffArtifactInvalid(logicalID: String)
    case approvalRunIDMismatch(logicalID: String)
    case approvalStageIDMismatch(logicalID: String)
    case approvalEvidenceMismatch(logicalID: String)
    case approvalReviewerRequired(logicalID: String)
    case approvalFromFuture(logicalID: String)
    case decisionBuildFailed(String)
    case decisionMismatch
    case decisionNotAuthorized
    case authorizationClockPrecedesDecision
    case authorizationBuildFailed(String)
}

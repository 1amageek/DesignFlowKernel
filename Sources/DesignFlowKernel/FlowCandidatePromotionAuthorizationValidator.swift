import Foundation
import CircuiteFoundation

public struct FlowCandidatePromotionAuthorizationValidator: Sendable {
    public init() {}

    public func validate(
        _ authorization: FlowCandidatePromotionAuthorization,
        decision: FlowCandidatePromotionDecision,
        request: FlowCandidatePromotionRequest,
        at currentTime: Date
    ) throws {
        do {
            try FlowCandidatePromotionDecisionValidator().validate(decision)
        } catch {
            throw FlowCandidatePromotionAuthorizationValidationError
                .decisionInvalid(String(describing: error))
        }
        let expectedAuthorizationDigest: ContentDigest
        do {
            expectedAuthorizationDigest = try FlowCandidatePromotionAuthorizationDigest.make(
                authorizationID: authorization.authorizationID,
                decisionID: authorization.decisionID,
                decisionDigest: authorization.decisionDigest,
                databaseID: authorization.databaseID,
                targetReferenceName: authorization.targetReferenceName,
                expectedGeneration: authorization.expectedGeneration,
                expectedRevision: authorization.expectedRevision,
                desiredRevision: authorization.desiredRevision,
                semanticGraphDigest: authorization.semanticGraphDigest,
                evidenceBindingDigest: authorization.evidenceBindingDigest,
                issuedAt: authorization.issuedAt,
                expiresAt: authorization.expiresAt
            )
        } catch {
            throw FlowCandidatePromotionAuthorizationValidationError
                .authorizationDigestComputationFailed(String(describing: error))
        }
        guard expectedAuthorizationDigest == authorization.authorizationDigest else {
            throw FlowCandidatePromotionAuthorizationValidationError
                .authorizationDigestMismatch(
                    expected: expectedAuthorizationDigest,
                    actual: authorization.authorizationDigest
                )
        }
        guard decision.verdict == .authorized else {
            throw FlowCandidatePromotionAuthorizationValidationError.decisionNotAuthorized
        }
        guard decision.runID == request.evidenceBinding.runID else {
            throw FlowCandidatePromotionAuthorizationValidationError
                .decisionRunIDMismatch
        }
        let requestedApprovals = request.approvalArtifacts.map(\.reference)
        guard decision.approvals.count == requestedApprovals.count,
              Set(decision.approvals) == Set(requestedApprovals) else {
            throw FlowCandidatePromotionAuthorizationValidationError
                .decisionApprovalArtifactsMismatch
        }
        guard authorization.decisionID == decision.decisionID,
              authorization.decisionDigest == decision.decisionDigest else {
            throw FlowCandidatePromotionAuthorizationValidationError.decisionIdentityMismatch
        }
        guard authorization.desiredRevision == decision.candidateRevision,
              authorization.desiredRevision == request.evidenceBinding.candidateRevision else {
            throw FlowCandidatePromotionAuthorizationValidationError.candidateRevisionMismatch
        }
        guard authorization.databaseID == authorization.desiredRevision.databaseID,
              authorization.databaseID == request.evidenceBinding.baseRevision.databaseID,
              authorization.expectedRevision?.databaseID == nil
                || authorization.expectedRevision?.databaseID == authorization.databaseID else {
            throw FlowCandidatePromotionAuthorizationValidationError.databaseMismatch
        }
        guard authorization.semanticGraphDigest == decision.semanticGraphDigest,
              authorization.semanticGraphDigest == request.evidenceBinding.semanticGraphDigest else {
            throw FlowCandidatePromotionAuthorizationValidationError.semanticGraphDigestMismatch
        }
        guard authorization.evidenceBindingDigest == decision.evidenceBindingDigest,
              authorization.evidenceBindingDigest == request.evidenceBinding.bindingDigest else {
            throw FlowCandidatePromotionAuthorizationValidationError.evidenceBindingDigestMismatch
        }
        guard decision.designDiff == request.designDiffArtifact.reference else {
            throw FlowCandidatePromotionAuthorizationValidationError
                .designDiffArtifactMismatch
        }
        guard authorization.targetReferenceName == request.targetReferenceName else {
            throw FlowCandidatePromotionAuthorizationValidationError.targetReferenceMismatch
        }
        guard authorization.expectedGeneration == request.expectedGeneration,
              authorization.expectedRevision == request.expectedRevision else {
            throw FlowCandidatePromotionAuthorizationValidationError.expectedReferenceStateMismatch
        }
        guard currentTime >= authorization.issuedAt else {
            throw FlowCandidatePromotionAuthorizationValidationError.authorizationNotYetValid
        }
        if let expiresAt = authorization.expiresAt, currentTime >= expiresAt {
            throw FlowCandidatePromotionAuthorizationValidationError.authorizationExpired
        }
    }
}

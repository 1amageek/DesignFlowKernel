import CircuiteFoundation

public struct FlowCandidatePromotionDecisionValidator: Sendable {
    public init() {}

    public func validate(
        _ decision: FlowCandidatePromotionDecision
    ) throws {
        for (field, value) in [
            ("decisionID", decision.decisionID),
            ("runID", decision.runID),
            ("policyID", decision.policyID),
            ("policyVersion", decision.policyVersion),
        ] where value.isEmpty {
            throw FlowCandidatePromotionDecisionValidationError.emptyField(field)
        }
        var reasonCodes = Set<String>()
        for reasonCode in decision.reasonCodes {
            guard !reasonCode.isEmpty else {
                throw FlowCandidatePromotionDecisionValidationError
                    .emptyField("reasonCode")
            }
            guard reasonCodes.insert(reasonCode).inserted else {
                throw FlowCandidatePromotionDecisionValidationError
                    .duplicateReasonCode(reasonCode)
            }
        }
        var approvalIDs = Set<ArtifactID>()
        for approval in decision.approvals
            where !approvalIDs.insert(approval.id).inserted {
            throw FlowCandidatePromotionDecisionValidationError
                .duplicateApproval(approval.id)
        }
        if decision.verdict == .authorized, decision.approvals.isEmpty {
            throw FlowCandidatePromotionDecisionValidationError
                .authorizedWithoutApproval
        }
        let expectedDigest: ContentDigest
        do {
            expectedDigest = try FlowCandidatePromotionDecisionDigest.make(
                decisionID: decision.decisionID,
                runID: decision.runID,
                candidateRevision: decision.candidateRevision,
                semanticGraphDigest: decision.semanticGraphDigest,
                evidenceBindingDigest: decision.evidenceBindingDigest,
                designDiff: decision.designDiff,
                verdict: decision.verdict,
                reasonCodes: decision.reasonCodes,
                approvals: decision.approvals,
                policyID: decision.policyID,
                policyVersion: decision.policyVersion,
                decidedAt: decision.decidedAt
            )
        } catch {
            throw FlowCandidatePromotionDecisionValidationError
                .decisionDigestComputationFailed(String(describing: error))
        }
        guard expectedDigest == decision.decisionDigest else {
            throw FlowCandidatePromotionDecisionValidationError
                .decisionDigestMismatch(
                    expected: expectedDigest,
                    actual: decision.decisionDigest
                )
        }
    }
}

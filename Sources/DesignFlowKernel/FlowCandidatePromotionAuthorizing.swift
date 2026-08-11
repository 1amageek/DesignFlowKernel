public protocol FlowCandidatePromotionAuthorizing: Sendable {
    func decidePromotion(
        _ request: FlowCandidatePromotionRequest
    ) async throws -> FlowCandidatePromotionDecision

    func issuePromotionAuthorization(
        for decision: FlowCandidatePromotionDecision,
        request: FlowCandidatePromotionRequest
    ) async throws -> FlowCandidatePromotionAuthorization
}

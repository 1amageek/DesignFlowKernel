public protocol FlowRunReviewLedgerLoading: Sendable {
    /// Loads structurally validated run metadata for per-artifact human review.
    ///
    /// The review consumer verifies each artifact independently so missing or
    /// corrupted evidence remains visible as structured review state.
    func loadRunLedgerForReview(runID: String) async throws -> FlowRunLedger
}

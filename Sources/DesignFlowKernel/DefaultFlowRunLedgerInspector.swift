import Foundation

public struct DefaultFlowRunLedgerInspector: FlowRunLedgerInspecting {
    private let reviewBundler: any FlowRunReviewBundling

    public init(reviewBundler: any FlowRunReviewBundling) {
        self.reviewBundler = reviewBundler
    }

    public func inspectRun(runID: String, workspaceID: FlowWorkspaceID) async throws -> FlowRunLedgerSummary {
        try await reviewBundler.makeReviewBundle(runID: runID, workspaceID: workspaceID).summary
    }
}

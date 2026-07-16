import Foundation

public struct DefaultFlowRunLedgerInspector: FlowRunLedgerInspecting {
    private let reviewBundler: any FlowRunReviewBundling

    public init(reviewBundler: any FlowRunReviewBundling) {
        self.reviewBundler = reviewBundler
    }

    public func inspectRun(runID: String, projectRoot: URL) async throws -> FlowRunLedgerSummary {
        try await reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot).summary
    }
}

import Foundation

public protocol FlowRunReviewBundling: Sendable {
    func makeReviewBundle(runID: String, workspaceID: FlowWorkspaceID) async throws -> FlowRunReviewBundle
}

import Foundation

public protocol FlowRunReviewBundling: Sendable {
    func makeReviewBundle(runID: String, projectRoot: URL) throws -> FlowRunReviewBundle
}

import Foundation

public struct FlowRunDesignDiffSummary: Sendable, Hashable, Codable {
    public var title: String
    public var actor: String
    public var reviewState: XcircuiteDesignDiffReviewState
    public var changeCount: Int
    public var domains: [XcircuiteDesignDiffDomain]

    public init(
        title: String,
        actor: String,
        reviewState: XcircuiteDesignDiffReviewState,
        changeCount: Int,
        domains: [XcircuiteDesignDiffDomain]
    ) {
        self.title = title
        self.actor = actor
        self.reviewState = reviewState
        self.changeCount = changeCount
        self.domains = domains
    }
}

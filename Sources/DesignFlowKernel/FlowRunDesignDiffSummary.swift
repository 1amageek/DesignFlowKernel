import Foundation

public struct FlowRunDesignDiffSummary: Sendable, Hashable, Codable {
    public var title: String
    public var actor: String
    public var reviewState: DesignDiffReviewState
    public var changeCount: Int
    public var domains: [DesignDiffDomain]

    public init(
        title: String,
        actor: String,
        reviewState: DesignDiffReviewState,
        changeCount: Int,
        domains: [DesignDiffDomain]
    ) {
        self.title = title
        self.actor = actor
        self.reviewState = reviewState
        self.changeCount = changeCount
        self.domains = domains
    }
}

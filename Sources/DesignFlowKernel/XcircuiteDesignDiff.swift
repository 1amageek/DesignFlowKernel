import Foundation

public struct XcircuiteDesignDiff: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var title: String
    public var actor: String
    public var reviewState: XcircuiteDesignDiffReviewState
    public var baseSnapshot: XcircuiteFileReference?
    public var proposedSnapshot: XcircuiteFileReference?
    public var changes: [XcircuiteDesignDiffChange]
    public var createdAt: Date

    public init(
        schemaVersion: Int = 1,
        runID: String,
        title: String,
        actor: String,
        reviewState: XcircuiteDesignDiffReviewState = .proposed,
        baseSnapshot: XcircuiteFileReference? = nil,
        proposedSnapshot: XcircuiteFileReference? = nil,
        changes: [XcircuiteDesignDiffChange],
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.title = title
        self.actor = actor
        self.reviewState = reviewState
        self.baseSnapshot = baseSnapshot
        self.proposedSnapshot = proposedSnapshot
        self.changes = changes
        self.createdAt = createdAt
    }
}

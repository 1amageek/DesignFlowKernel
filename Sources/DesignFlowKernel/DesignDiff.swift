import Foundation

public struct DesignDiff: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var title: String
    public var actor: String
    public var reviewState: DesignDiffReviewState
    public var baseSnapshot: ArtifactReference?
    public var proposedSnapshot: ArtifactReference?
    public var changes: [DesignDiffChange]
    public var createdAt: Date

    public init(
        schemaVersion: Int = 1,
        runID: String,
        title: String,
        actor: String,
        reviewState: DesignDiffReviewState = .proposed,
        baseSnapshot: ArtifactReference? = nil,
        proposedSnapshot: ArtifactReference? = nil,
        changes: [DesignDiffChange],
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

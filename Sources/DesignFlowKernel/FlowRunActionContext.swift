import Foundation

public struct FlowRunActionContext: Sendable, Hashable, Codable {
    public struct ArtifactEdit: Sendable, Hashable, Codable {
        public var proposalID: String
        public var targetPath: String
        public var operation: String

        public init(
            proposalID: String,
            targetPath: String,
            operation: String
        ) {
            self.proposalID = proposalID
            self.targetPath = targetPath
            self.operation = operation
        }
    }

    public struct ReviewDecision: Sendable, Hashable, Codable {
        public var kind: FlowRunReviewDecisionKind
        public var decision: String
        public var targetID: String
        public var targetPath: String?
        public var reason: String

        public init(
            kind: FlowRunReviewDecisionKind,
            decision: String,
            targetID: String,
            targetPath: String? = nil,
            reason: String
        ) {
            self.kind = kind
            self.decision = decision
            self.targetID = targetID
            self.targetPath = targetPath
            self.reason = reason
        }
    }

    public struct SuggestedAction: Sendable, Hashable, Codable {
        public var nextActionID: String
        public var nextActionKind: String
        public var action: FlowRunSuggestedAction

        public init(
            nextActionID: String,
            nextActionKind: String,
            action: FlowRunSuggestedAction
        ) {
            self.nextActionID = nextActionID
            self.nextActionKind = nextActionKind
            self.action = action
        }
    }

    public var iterationID: String?
    public var artifactEdit: ArtifactEdit?
    public var reviewDecision: ReviewDecision?
    public var suggestedAction: SuggestedAction?

    public init(
        iterationID: String? = nil,
        artifactEdit: ArtifactEdit? = nil,
        reviewDecision: ReviewDecision? = nil,
        suggestedAction: SuggestedAction? = nil
    ) {
        self.iterationID = iterationID
        self.artifactEdit = artifactEdit
        self.reviewDecision = reviewDecision
        self.suggestedAction = suggestedAction
    }
}

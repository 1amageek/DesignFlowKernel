import Foundation

public struct FlowRunActionContext: Sendable, Hashable, Codable {
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

    public struct SuggestedCommand: Sendable, Hashable, Codable {
        public var nextActionID: String
        public var nextActionKind: String
        public var commandID: String
        public var readiness: String
        public var executable: String
        public var arguments: [String]
        public var reason: String

        public init(
            nextActionID: String,
            nextActionKind: String,
            commandID: String,
            readiness: String,
            executable: String,
            arguments: [String],
            reason: String
        ) {
            self.nextActionID = nextActionID
            self.nextActionKind = nextActionKind
            self.commandID = commandID
            self.readiness = readiness
            self.executable = executable
            self.arguments = arguments
            self.reason = reason
        }
    }

    public var iterationID: String?
    public var reviewDecision: ReviewDecision?
    public var suggestedCommand: SuggestedCommand?

    public init(
        iterationID: String? = nil,
        reviewDecision: ReviewDecision? = nil,
        suggestedCommand: SuggestedCommand? = nil
    ) {
        self.iterationID = iterationID
        self.reviewDecision = reviewDecision
        self.suggestedCommand = suggestedCommand
    }
}

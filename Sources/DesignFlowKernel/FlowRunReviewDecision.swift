import Foundation

public struct FlowRunReviewDecision: Sendable, Hashable, Codable {
    public var actionRecordID: String
    public var runID: String
    public var stageID: String?
    public var actor: FlowRunActor
    public var status: FlowRunActionStatus
    public var decidedAt: Date
    public var decisionKind: FlowRunReviewDecisionKind
    public var decision: String
    public var targetID: String
    public var targetPath: String?
    public var reason: String

    public init(
        actionRecordID: String,
        runID: String,
        stageID: String?,
        actor: FlowRunActor,
        status: FlowRunActionStatus,
        decidedAt: Date,
        decisionKind: FlowRunReviewDecisionKind,
        decision: String,
        targetID: String,
        targetPath: String?,
        reason: String
    ) {
        self.actionRecordID = actionRecordID
        self.runID = runID
        self.stageID = stageID
        self.actor = actor
        self.status = status
        self.decidedAt = decidedAt
        self.decisionKind = decisionKind
        self.decision = decision
        self.targetID = targetID
        self.targetPath = targetPath
        self.reason = reason
    }

    public init?(record: FlowRunActionRecord) throws {
        guard let decisionKind = FlowRunReviewDecisionKind(rawValue: record.actionKind) else {
            return nil
        }
        guard let details = record.context.reviewDecision else {
            throw FlowRunActionProjectionError.missingReviewDecisionMetadata(
                actionID: record.actionID,
                key: "reviewDecision"
            )
        }
        self.init(
            actionRecordID: record.actionID,
            runID: record.runID,
            stageID: record.stageID,
            actor: record.actor,
            status: record.status,
            decidedAt: record.createdAt,
            decisionKind: decisionKind,
            decision: details.decision,
            targetID: details.targetID,
            targetPath: details.targetPath,
            reason: details.reason
        )
    }
}

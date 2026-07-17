import Foundation

public struct FlowRunSuggestedActionSelection: Sendable, Hashable, Codable {
    public static let actionKind = "review.selectSuggestedAction"

    public var actionRecordID: String
    public var runID: String
    public var actor: FlowRunActor
    public var status: FlowRunActionStatus
    public var selectedAt: Date
    public var nextActionID: String
    public var nextActionKind: String
    public var action: FlowRunSuggestedAction

    public init(
        actionRecordID: String,
        runID: String,
        actor: FlowRunActor,
        status: FlowRunActionStatus,
        selectedAt: Date,
        nextActionID: String,
        nextActionKind: String,
        action: FlowRunSuggestedAction
    ) {
        self.actionRecordID = actionRecordID
        self.runID = runID
        self.actor = actor
        self.status = status
        self.selectedAt = selectedAt
        self.nextActionID = nextActionID
        self.nextActionKind = nextActionKind
        self.action = action
    }

    public init?(record: FlowRunActionRecord) throws {
        guard record.actionKind == Self.actionKind else {
            return nil
        }
        guard let details = record.context.suggestedAction else {
            throw FlowRunActionProjectionError.missingSelectionMetadata(
                actionID: record.actionID,
                key: "suggestedAction"
            )
        }
        self.init(
            actionRecordID: record.actionID,
            runID: record.runID,
            actor: record.actor,
            status: record.status,
            selectedAt: record.createdAt,
            nextActionID: details.nextActionID,
            nextActionKind: details.nextActionKind,
            action: details.action
        )
    }
}

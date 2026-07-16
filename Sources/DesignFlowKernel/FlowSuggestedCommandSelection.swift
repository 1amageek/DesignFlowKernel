import Foundation

public struct FlowSuggestedCommandSelection: Sendable, Hashable, Codable {
    public static let actionKind = "review.selectSuggestedCommand"

    public var actionRecordID: String
    public var runID: String
    public var actor: FlowRunActor
    public var status: FlowRunActionStatus
    public var selectedAt: Date
    public var nextActionID: String
    public var nextActionKind: String
    public var commandID: String
    public var readiness: String
    public var executable: String
    public var arguments: [String]
    public var reason: String

    public init(
        actionRecordID: String,
        runID: String,
        actor: FlowRunActor,
        status: FlowRunActionStatus,
        selectedAt: Date,
        nextActionID: String,
        nextActionKind: String,
        commandID: String,
        readiness: String,
        executable: String,
        arguments: [String],
        reason: String
    ) {
        self.actionRecordID = actionRecordID
        self.runID = runID
        self.actor = actor
        self.status = status
        self.selectedAt = selectedAt
        self.nextActionID = nextActionID
        self.nextActionKind = nextActionKind
        self.commandID = commandID
        self.readiness = readiness
        self.executable = executable
        self.arguments = arguments
        self.reason = reason
    }

    public init?(record: FlowRunActionRecord) throws {
        guard record.actionKind == Self.actionKind else {
            return nil
        }
        guard let details = record.context.suggestedCommand else {
            throw FlowRunActionProjectionError.missingSelectionMetadata(
                actionID: record.actionID,
                key: "suggestedCommand"
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
            commandID: details.commandID,
            readiness: details.readiness,
            executable: details.executable,
            arguments: details.arguments,
            reason: details.reason
        )
    }
}

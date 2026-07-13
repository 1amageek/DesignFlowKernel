import Foundation

public struct XcircuiteSuggestedCommandSelection: Sendable, Hashable, Codable {
    public static let actionKind = "review.selectSuggestedCommand"

    public var actionRecordID: String
    public var runID: String
    public var actor: XcircuiteRunActionActor
    public var status: XcircuiteRunActionStatus
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
        actor: XcircuiteRunActionActor,
        status: XcircuiteRunActionStatus,
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

    public init?(record: XcircuiteRunActionRecord) throws {
        guard record.actionKind == Self.actionKind else {
            return nil
        }
        self.init(
            actionRecordID: record.actionID,
            runID: record.runID,
            actor: record.actor,
            status: record.status,
            selectedAt: record.createdAt,
            nextActionID: try Self.requiredString("nextActionID", in: record),
            nextActionKind: try Self.requiredString("nextActionKind", in: record),
            commandID: try Self.requiredString("commandID", in: record),
            readiness: try Self.requiredString("readiness", in: record),
            executable: try Self.requiredString("executable", in: record),
            arguments: try Self.requiredStringArray("arguments", in: record),
            reason: try Self.requiredString("reason", in: record)
        )
    }

    private static func requiredString(
        _ key: String,
        in record: XcircuiteRunActionRecord
    ) throws -> String {
        guard let value = record.metadata[key] else {
            throw XcircuiteRunActionProjectionError.missingSelectionMetadata(
                actionID: record.actionID,
                key: key
            )
        }
        guard case .string(let string) = value else {
            throw XcircuiteRunActionProjectionError.invalidSelectionMetadata(
                actionID: record.actionID,
                key: key
            )
        }
        return string
    }

    private static func requiredStringArray(
        _ key: String,
        in record: XcircuiteRunActionRecord
    ) throws -> [String] {
        guard let value = record.metadata[key] else {
            throw XcircuiteRunActionProjectionError.missingSelectionMetadata(
                actionID: record.actionID,
                key: key
            )
        }
        guard case .array(let values) = value else {
            throw XcircuiteRunActionProjectionError.invalidSelectionMetadata(
                actionID: record.actionID,
                key: key
            )
        }
        return try values.map { value in
            guard case .string(let string) = value else {
                throw XcircuiteRunActionProjectionError.invalidSelectionMetadata(
                    actionID: record.actionID,
                    key: key
                )
            }
            return string
        }
    }
}

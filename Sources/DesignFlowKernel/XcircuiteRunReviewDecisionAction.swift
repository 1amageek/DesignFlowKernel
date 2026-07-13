import Foundation

public struct XcircuiteRunReviewDecisionAction: Sendable, Hashable, Codable {
    public var actionRecordID: String
    public var runID: String
    public var stageID: String?
    public var actor: XcircuiteRunActionActor
    public var status: XcircuiteRunActionStatus
    public var decidedAt: Date
    public var decisionKind: XcircuiteRunReviewDecisionActionKind
    public var decision: String
    public var targetID: String
    public var targetPath: String?
    public var reason: String
    public var metadata: [String: XcircuiteJSONValue]

    public init(
        actionRecordID: String,
        runID: String,
        stageID: String?,
        actor: XcircuiteRunActionActor,
        status: XcircuiteRunActionStatus,
        decidedAt: Date,
        decisionKind: XcircuiteRunReviewDecisionActionKind,
        decision: String,
        targetID: String,
        targetPath: String?,
        reason: String,
        metadata: [String: XcircuiteJSONValue]
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
        self.metadata = metadata
    }

    public init?(record: XcircuiteRunActionRecord) throws {
        guard let decisionKind = XcircuiteRunReviewDecisionActionKind(rawValue: record.actionKind) else {
            return nil
        }
        self.init(
            actionRecordID: record.actionID,
            runID: record.runID,
            stageID: record.stageID,
            actor: record.actor,
            status: record.status,
            decidedAt: record.createdAt,
            decisionKind: decisionKind,
            decision: try Self.requiredString("decision", in: record),
            targetID: try Self.requiredString("targetID", in: record),
            targetPath: try Self.optionalString("targetPath", in: record),
            reason: try Self.requiredString("reason", in: record),
            metadata: record.metadata
        )
    }

    private static func requiredString(
        _ key: String,
        in record: XcircuiteRunActionRecord
    ) throws -> String {
        guard let value = record.metadata[key] else {
            throw XcircuiteRunActionProjectionError.missingReviewDecisionMetadata(
                actionID: record.actionID,
                key: key
            )
        }
        guard case .string(let string) = value else {
            throw XcircuiteRunActionProjectionError.invalidReviewDecisionMetadata(
                actionID: record.actionID,
                key: key
            )
        }
        return string
    }

    private static func optionalString(
        _ key: String,
        in record: XcircuiteRunActionRecord
    ) throws -> String? {
        guard let value = record.metadata[key] else {
            return nil
        }
        guard case .string(let string) = value else {
            throw XcircuiteRunActionProjectionError.invalidReviewDecisionMetadata(
                actionID: record.actionID,
                key: key
            )
        }
        return string
    }
}

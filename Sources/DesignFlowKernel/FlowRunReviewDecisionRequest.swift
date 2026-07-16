import CircuiteFoundation
import Foundation

public struct FlowRunReviewDecisionRequest: Sendable, Hashable, Codable {
    public var actionID: String
    public var runID: String
    public var stageID: String?
    public var actor: FlowRunActor
    public var decisionKind: FlowRunReviewDecisionKind
    public var decision: String
    public var targetID: String
    public var targetPath: String?
    public var reason: String
    public var status: FlowRunActionStatus
    public var inputs: [ArtifactReference]
    public var outputs: [ArtifactReference]
    public var diagnostics: [FlowRunDiagnostic]
    public var createdAt: Date

    public init(
        actionID: String,
        runID: String,
        stageID: String? = nil,
        actor: FlowRunActor,
        decisionKind: FlowRunReviewDecisionKind,
        decision: String,
        targetID: String,
        targetPath: String? = nil,
        reason: String = "",
        status: FlowRunActionStatus = .succeeded,
        inputs: [ArtifactReference] = [],
        outputs: [ArtifactReference] = [],
        diagnostics: [FlowRunDiagnostic] = [],
        createdAt: Date = Date()
    ) {
        self.actionID = actionID
        self.runID = runID
        self.stageID = stageID
        self.actor = actor
        self.decisionKind = decisionKind
        self.decision = decision
        self.targetID = targetID
        self.targetPath = targetPath
        self.reason = reason
        self.status = status
        self.inputs = inputs
        self.outputs = outputs
        self.diagnostics = diagnostics
        self.createdAt = createdAt
    }
}

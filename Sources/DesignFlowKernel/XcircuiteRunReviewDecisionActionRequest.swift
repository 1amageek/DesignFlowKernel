import Foundation

public struct XcircuiteRunReviewDecisionActionRequest: Sendable, Hashable, Codable {
    public var actionID: String
    public var runID: String
    public var stageID: String?
    public var actor: XcircuiteRunActionActor
    public var decisionKind: XcircuiteRunReviewDecisionActionKind
    public var decision: String
    public var targetID: String
    public var targetPath: String?
    public var reason: String
    public var status: XcircuiteRunActionStatus
    public var inputs: [XcircuiteFileReference]
    public var outputs: [XcircuiteFileReference]
    public var diagnostics: [XcircuiteRunActionDiagnostic]
    public var metadata: [String: XcircuiteJSONValue]
    public var createdAt: Date

    public init(
        actionID: String,
        runID: String,
        stageID: String? = nil,
        actor: XcircuiteRunActionActor,
        decisionKind: XcircuiteRunReviewDecisionActionKind,
        decision: String,
        targetID: String,
        targetPath: String? = nil,
        reason: String = "",
        status: XcircuiteRunActionStatus = .succeeded,
        inputs: [XcircuiteFileReference] = [],
        outputs: [XcircuiteFileReference] = [],
        diagnostics: [XcircuiteRunActionDiagnostic] = [],
        metadata: [String: XcircuiteJSONValue] = [:],
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
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

import Foundation

public struct FlowRunNextAction: Sendable, Hashable, Codable {
    public var actionID: String
    public var kind: String
    public var stageID: String?
    public var severity: FlowDiagnosticSeverity
    public var reason: String
    public var diagnosticCodes: [String]
    public var suggestedActions: [FlowRunSuggestedAction]

    public init(
        actionID: String,
        kind: String,
        stageID: String? = nil,
        severity: FlowDiagnosticSeverity,
        reason: String,
        diagnosticCodes: [String] = [],
        suggestedActions: [FlowRunSuggestedAction] = []
    ) {
        self.actionID = actionID
        self.kind = kind
        self.stageID = stageID
        self.severity = severity
        self.reason = reason
        self.diagnosticCodes = diagnosticCodes
        self.suggestedActions = suggestedActions
    }

}

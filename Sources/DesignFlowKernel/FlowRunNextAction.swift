import Foundation

public struct FlowRunNextAction: Sendable, Hashable, Codable {
    public var actionID: String
    public var kind: String
    public var stageID: String?
    public var severity: FlowDiagnosticSeverity
    public var reason: String
    public var diagnosticCodes: [String]
    public var suggestedCommands: [FlowRunSuggestedCommand]

    public init(
        actionID: String,
        kind: String,
        stageID: String? = nil,
        severity: FlowDiagnosticSeverity,
        reason: String,
        diagnosticCodes: [String] = [],
        suggestedCommands: [FlowRunSuggestedCommand] = []
    ) {
        self.actionID = actionID
        self.kind = kind
        self.stageID = stageID
        self.severity = severity
        self.reason = reason
        self.diagnosticCodes = diagnosticCodes
        self.suggestedCommands = suggestedCommands
    }

}

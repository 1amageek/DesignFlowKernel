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

    private enum CodingKeys: String, CodingKey {
        case actionID
        case kind
        case stageID
        case severity
        case reason
        case diagnosticCodes
        case suggestedCommands
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.actionID = try container.decode(String.self, forKey: .actionID)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.stageID = try container.decodeIfPresent(String.self, forKey: .stageID)
        self.severity = try container.decode(FlowDiagnosticSeverity.self, forKey: .severity)
        self.reason = try container.decode(String.self, forKey: .reason)
        self.diagnosticCodes = try container.decodeIfPresent(
            [String].self,
            forKey: .diagnosticCodes
        ) ?? []
        self.suggestedCommands = try container.decodeIfPresent(
            [FlowRunSuggestedCommand].self,
            forKey: .suggestedCommands
        ) ?? []
    }
}

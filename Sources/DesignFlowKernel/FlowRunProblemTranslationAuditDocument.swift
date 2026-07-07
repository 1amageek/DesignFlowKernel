import Foundation

struct FlowRunProblemTranslationAuditDocument: Sendable, Decodable {
    var status: String
    var problemID: String?
    var blocking: Bool
    var diagnostics: [FlowRunProblemTranslationAuditDiagnostic]
    var nextActions: [String]

    var diagnosticCodes: [String] {
        diagnostics.map(\.code)
    }

    var primaryNextAction: String {
        nextActions.first ?? "repair-problem-translation-audit"
    }

    var summary: String {
        if let firstMessage = diagnostics.compactMap(\.message).first, !firstMessage.isEmpty {
            return firstMessage
        }
        if let problemID {
            return "Problem translation audit is blocking planner entry for \(problemID)."
        }
        return "Problem translation audit is blocking planner entry."
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case problemID
        case blocking
        case diagnostics
        case nextActions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        self.problemID = try container.decodeIfPresent(String.self, forKey: .problemID)
        self.blocking = try container.decodeIfPresent(Bool.self, forKey: .blocking) ?? false
        self.diagnostics = try container.decodeIfPresent(
            [FlowRunProblemTranslationAuditDiagnostic].self,
            forKey: .diagnostics
        ) ?? []
        self.nextActions = try container.decodeIfPresent([String].self, forKey: .nextActions) ?? []
    }
}

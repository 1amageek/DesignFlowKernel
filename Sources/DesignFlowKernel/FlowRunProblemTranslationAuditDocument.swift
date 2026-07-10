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

}

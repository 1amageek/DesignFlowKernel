import Foundation

struct FlowRunProblemTranslationAuditDiagnostic: Sendable, Decodable, Hashable {
    var severity: String
    var code: String
    var message: String?
    var nextActions: [String]

    private enum CodingKeys: String, CodingKey {
        case severity
        case code
        case message
        case nextActions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.severity = try container.decodeIfPresent(String.self, forKey: .severity) ?? "warning"
        self.code = try container.decodeIfPresent(String.self, forKey: .code) ?? "problem-translation-audit-diagnostic"
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        self.nextActions = try container.decodeIfPresent([String].self, forKey: .nextActions) ?? []
    }
}

import Foundation

struct FlowRunProblemTranslationAuditDiagnostic: Sendable, Decodable, Hashable {
    var severity: String
    var code: String
    var message: String?
    var nextActions: [String]

}

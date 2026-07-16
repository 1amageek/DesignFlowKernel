import Foundation

public struct FlowRunDiagnostic: Sendable, Hashable, Codable {
    public var severity: FlowRunDiagnosticSeverity
    public var code: String
    public var message: String

    public init(
        severity: FlowRunDiagnosticSeverity,
        code: String,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}

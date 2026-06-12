import Foundation

public struct FlowDiagnostic: Sendable, Hashable, Codable {
    public var severity: FlowDiagnosticSeverity
    public var code: String
    public var message: String

    public init(severity: FlowDiagnosticSeverity, code: String, message: String) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}

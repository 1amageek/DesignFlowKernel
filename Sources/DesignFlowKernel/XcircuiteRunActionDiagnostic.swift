import Foundation

public struct XcircuiteRunActionDiagnostic: Sendable, Hashable, Codable {
    public var severity: XcircuiteRunActionDiagnosticSeverity
    public var code: String
    public var message: String

    public init(
        severity: XcircuiteRunActionDiagnosticSeverity,
        code: String,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}

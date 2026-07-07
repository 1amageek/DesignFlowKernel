import Foundation

public struct DesignFlowCLIErrorDiagnostic: Codable, Sendable, Hashable {
    public let severity: String
    public let code: String
    public let message: String
    public let option: String?
    public let value: String?
    public let expected: String?
    public let suggestedActions: [String]

    public init(
        severity: String,
        code: String,
        message: String,
        option: String? = nil,
        value: String? = nil,
        expected: String? = nil,
        suggestedActions: [String] = []
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.option = option
        self.value = value
        self.expected = expected
        self.suggestedActions = suggestedActions
    }
}

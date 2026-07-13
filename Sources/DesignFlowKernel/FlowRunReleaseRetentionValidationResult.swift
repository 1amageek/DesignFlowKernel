import Foundation

public struct FlowRunReleaseRetentionValidationResult: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case passed
        case blocked
    }

    public var status: Status
    public var diagnostics: [FlowDiagnostic]

    public init(status: Status, diagnostics: [FlowDiagnostic] = []) {
        self.status = status
        self.diagnostics = diagnostics
    }
}

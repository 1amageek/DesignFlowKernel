import Foundation

public struct FlowStageRetryDecision: Sendable, Hashable, Codable {
    public var shouldRetry: Bool
    public var reason: FlowStageRetryDecisionReason
    public var matchedDiagnosticCodes: [String]

    public init(
        shouldRetry: Bool,
        reason: FlowStageRetryDecisionReason,
        matchedDiagnosticCodes: [String] = []
    ) {
        self.shouldRetry = shouldRetry
        self.reason = reason
        self.matchedDiagnosticCodes = matchedDiagnosticCodes
    }
}

import Foundation

public enum FlowStageRetryDecisionReason: String, Sendable, Hashable, Codable {
    case notRetryable
    case retryableDiagnosticMatched
    case maxAttemptsReached
    case stageDidNotFail
    case cancellationObserved
}

import Foundation

public enum FlowRunProgressEventKind: String, Sendable, Hashable, Codable {
    case runStarted
    case stageStarted
    case stageFinished
    case stageBlocked
    case stageFailed
    case stageRetryScheduled
    case runFinished
    case cancellationRequested
    case cancellationObserved
}

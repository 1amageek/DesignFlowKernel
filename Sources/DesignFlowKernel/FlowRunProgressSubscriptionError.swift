import Foundation

public enum FlowRunProgressSubscriptionError: Error, LocalizedError, Equatable {
    case invalidSequence(Int)
    case invalidTimeoutMilliseconds(Int)
    case invalidPollIntervalMilliseconds(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidSequence(let sequence):
            "Progress sequence must be zero or greater, got \(sequence)."
        case .invalidTimeoutMilliseconds(let milliseconds):
            "Progress subscription timeout must be zero or greater, got \(milliseconds)."
        case .invalidPollIntervalMilliseconds(let milliseconds):
            "Progress subscription poll interval must be greater than zero, got \(milliseconds)."
        }
    }
}

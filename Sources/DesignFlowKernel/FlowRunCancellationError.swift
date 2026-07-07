import Foundation

public enum FlowRunCancellationError: Error, Sendable, Equatable {
    case requested(FlowRunCancellationRequest)

    public var request: FlowRunCancellationRequest {
        switch self {
        case let .requested(request):
            request
        }
    }
}

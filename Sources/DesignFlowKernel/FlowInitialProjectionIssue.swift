import Foundation

public enum FlowInitialProjectionIssue: Sendable, Equatable, LocalizedError {
    case containsLifecycleProjection

    public var errorDescription: String? {
        switch self {
        case .containsLifecycleProjection:
            "A new run may contain only a revision-zero created manifest and an optional plan."
        }
    }
}

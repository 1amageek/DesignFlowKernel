import Foundation

public enum FlowWorkspaceIDError: Error, LocalizedError, Sendable, Equatable {
    case invalidValue(String)

    public var errorDescription: String? {
        switch self {
        case .invalidValue(let value):
            "Invalid flow workspace identifier: \(value)"
        }
    }
}

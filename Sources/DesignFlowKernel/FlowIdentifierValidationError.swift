import Foundation

public enum FlowIdentifierValidationError: Error, Sendable, Equatable, LocalizedError {
    case invalidIdentifier(kind: String, value: String)

    public var errorDescription: String? {
        switch self {
        case .invalidIdentifier(let kind, let value):
            return "Invalid \(kind): \(value)."
        }
    }
}

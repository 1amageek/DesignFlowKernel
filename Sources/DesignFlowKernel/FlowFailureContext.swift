import Foundation

public struct FlowFailureContext: Sendable, Equatable, Codable {
    public let errorType: String
    public let message: String

    public init(errorType: String, message: String) {
        self.errorType = errorType
        self.message = message
    }

    public init(capturing error: any Error) {
        self.errorType = String(reflecting: type(of: error))
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription {
            self.message = description
        } else {
            self.message = String(describing: error)
        }
    }
}

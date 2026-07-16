import Foundation

public struct FlowIdentifierValidator: Sendable {
    private let allowedScalars = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    )
    private let maximumLength: Int

    public init(maximumLength: Int = 128) {
        self.maximumLength = maximumLength
    }

    public func validate(_ value: String, kind: FlowIdentifierKind) throws {
        let isValid = !value.isEmpty
            && value.count <= maximumLength
            && value != "."
            && value != ".."
            && value.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
        guard isValid else {
            throw FlowIdentifierValidationError.invalidIdentifier(
                kind: kind.rawValue,
                value: value
            )
        }
    }
}

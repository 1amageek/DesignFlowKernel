import Foundation

@propertyWrapper
public struct FlowSchemaVersion2: Sendable, Hashable, Codable {
    public static let currentValue = 2

    public var wrappedValue: Int

    public init(wrappedValue: Int) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Int.self)
        guard value == Self.currentValue else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected flow schema version \(Self.currentValue)."
            )
        }
        wrappedValue = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

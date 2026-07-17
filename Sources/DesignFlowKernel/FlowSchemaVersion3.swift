import Foundation

@propertyWrapper
public struct FlowSchemaVersion3: Sendable, Hashable, Codable {
    public static let currentValue = 3

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

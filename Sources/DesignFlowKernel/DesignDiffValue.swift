import Foundation

public enum DesignDiffValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([DesignDiffValue])
    case object([String: DesignDiffValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            self = try Self.decodeNonNullValue(from: container)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    private static func decodeNonNullValue(
        from container: SingleValueDecodingContainer
    ) throws -> DesignDiffValue {
        do {
            return .bool(try container.decode(Bool.self))
        } catch {
            return try decodeNonBoolValue(from: container)
        }
    }

    private static func decodeNonBoolValue(
        from container: SingleValueDecodingContainer
    ) throws -> DesignDiffValue {
        do {
            return .number(try container.decode(Double.self))
        } catch {
            return try decodeNonNumberValue(from: container)
        }
    }

    private static func decodeNonNumberValue(
        from container: SingleValueDecodingContainer
    ) throws -> DesignDiffValue {
        do {
            return .string(try container.decode(String.self))
        } catch {
            return try decodeStructuredValue(from: container)
        }
    }

    private static func decodeStructuredValue(
        from container: SingleValueDecodingContainer
    ) throws -> DesignDiffValue {
        do {
            return .array(try container.decode([DesignDiffValue].self))
        } catch {
            return .object(try container.decode([String: DesignDiffValue].self))
        }
    }
}

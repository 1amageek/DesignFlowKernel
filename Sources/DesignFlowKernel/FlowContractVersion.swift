import Foundation

public enum FlowContractVersion: Sendable, Hashable, Codable {
    case integer(Int)
    case text(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            let integer = try container.decode(Int.self)
            self = .integer(integer)
            return
        } catch {
            self = .text(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let value):
            try container.encode(value)
        case .text(let value):
            try container.encode(value)
        }
    }
}

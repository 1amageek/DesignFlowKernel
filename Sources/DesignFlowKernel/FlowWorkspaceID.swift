import Foundation

/// Opaque identity for a workspace bound to injected flow persistence.
///
/// This value is deliberately not a path. Applications resolve it to their
/// own storage namespace before constructing kernel infrastructure.
public struct FlowWorkspaceID: Sendable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) throws {
        do {
            try FlowIdentifierValidator().validate(rawValue, kind: .projectID)
        } catch {
            throw FlowWorkspaceIDError.invalidValue(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

import Foundation

public struct XcircuiteRunActionActor: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case agent
        case human
        case cli
        case system
    }

    public var kind: Kind
    public var identifier: String

    public init(kind: Kind, identifier: String) {
        self.kind = kind
        self.identifier = identifier
    }
}

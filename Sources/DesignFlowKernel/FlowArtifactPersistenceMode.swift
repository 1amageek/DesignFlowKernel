import Foundation

public enum FlowArtifactPersistenceMode: Sendable, Hashable, Codable {
    /// Creates a new artifact and rejects any existing item at the destination.
    case createOnly

    /// Preserves existing content while allowing an identical write to be retried.
    case immutable

    /// Atomically replaces existing content at the destination.
    case replaceable

    /// Extends an audit artifact without permitting existing bytes to change.
    case appendOnly
}

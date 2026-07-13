import Foundation

@available(*, deprecated, message: "Use a domain-specific request protocol.")
public protocol XcircuiteEngineRequest: Sendable, Hashable, Codable {
    var schemaVersion: Int { get }
    var runID: String { get }
    var inputs: [XcircuiteFileReference] { get }
}

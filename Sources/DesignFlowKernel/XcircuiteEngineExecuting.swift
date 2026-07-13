import Foundation

@available(*, deprecated, message: "Use CircuiteFoundation.Engine directly.")
public protocol XcircuiteEngineExecuting: Sendable {
    associatedtype Request: XcircuiteEngineRequest
    associatedtype Payload: Sendable & Hashable & Codable

    func execute(
        _ request: Request
    ) async throws -> XcircuiteEngineResultEnvelope<Payload>
}

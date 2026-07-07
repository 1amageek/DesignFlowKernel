import Foundation

public struct FlowRunCancellationResult: Sendable, Hashable, Codable {
    public var status: String
    public var request: FlowRunCancellationRequest
    public var path: String

    public init(
        status: String,
        request: FlowRunCancellationRequest,
        path: String
    ) {
        self.status = status
        self.request = request
        self.path = path
    }
}

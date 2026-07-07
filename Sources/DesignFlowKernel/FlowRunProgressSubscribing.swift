import Foundation

public protocol FlowRunProgressSubscribing: Sendable {
    func snapshot(
        request: FlowRunProgressSubscriptionRequest
    ) throws -> FlowRunProgressSnapshot

    func waitForProgress(
        request: FlowRunProgressSubscriptionRequest
    ) async throws -> FlowRunProgressSnapshot

    func followProgress(
        request: FlowRunProgressSubscriptionRequest,
        onEvent: @Sendable (FlowRunProgressEvent) async throws -> Void
    ) async throws -> FlowRunProgressSnapshot
}

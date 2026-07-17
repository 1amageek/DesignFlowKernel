import Foundation

public struct FlowRunSuggestedAction: Sendable, Hashable, Codable {
    public var id: String
    public var readiness: FlowRunSuggestedActionReadiness
    public var operation: FlowRunSuggestedOperation
    public var runID: String?
    public var reason: String

    public init(
        id: String,
        readiness: FlowRunSuggestedActionReadiness,
        operation: FlowRunSuggestedOperation,
        runID: String?,
        reason: String
    ) {
        self.id = id
        self.readiness = readiness
        self.operation = operation
        self.runID = runID
        self.reason = reason
    }
}

import Foundation
import ToolQualification

public struct FlowExecutionContext: Sendable {
    public var projectRoot: URL
    public var runID: String
    public var runDirectory: URL
    /// Storage capabilities exposed to stage executors.
    public var storage: any FlowExecutionStorage
    public var toolRegistry: ToolRegistry
    public var healthResults: [String: ToolHealthCheckResult]

    public init(
        projectRoot: URL,
        runID: String,
        runDirectory: URL,
        storage: any FlowExecutionStorage,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult]
    ) {
        self.projectRoot = projectRoot
        self.runID = runID
        self.runDirectory = runDirectory
        self.storage = storage
        self.toolRegistry = toolRegistry
        self.healthResults = healthResults
    }

    public func loadCancellationRequest() throws -> FlowRunCancellationRequest? {
        try storage.loadCancellationRequest(
            runID: runID,
            projectRoot: projectRoot
        )
    }

    public func checkCancellation() throws {
        if let request = try loadCancellationRequest() {
            throw FlowRunCancellationError.requested(request)
        }
    }
}

import Foundation
import ToolQualification

public struct FlowExecutionContext: Sendable {
    public var projectRoot: URL
    public var runID: String
    public var runDirectory: URL
    /// Storage capabilities exposed to stage executors.
    ///
    /// `packageStore` remains as a source-compatible spelling during the
    /// migration, but its static type is the protocol so the execution
    /// context no longer requires a concrete filesystem store.
    public var packageStore: any FlowExecutionStorage
    public var toolRegistry: ToolRegistry
    public var healthResults: [String: ToolHealthCheckResult]

    /// Protocol-oriented spelling for new callers. It aliases
    /// `packageStore` without exposing a concrete workspace implementation.
    public var storage: any FlowExecutionStorage {
        get { packageStore }
        set { packageStore = newValue }
    }

    public init(
        projectRoot: URL,
        runID: String,
        runDirectory: URL,
        packageStore: any FlowExecutionStorage,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult]
    ) {
        self.projectRoot = projectRoot
        self.runID = runID
        self.runDirectory = runDirectory
        self.packageStore = packageStore
        self.toolRegistry = toolRegistry
        self.healthResults = healthResults
    }

    public init(
        projectRoot: URL,
        runID: String,
        runDirectory: URL,
        storage: any FlowExecutionStorage,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult]
    ) {
        self.init(
            projectRoot: projectRoot,
            runID: runID,
            runDirectory: runDirectory,
            packageStore: storage,
            toolRegistry: toolRegistry,
            healthResults: healthResults
        )
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

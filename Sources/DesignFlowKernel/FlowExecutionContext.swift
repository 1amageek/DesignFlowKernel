import Foundation
import ToolQualification

public struct FlowExecutionContext: Sendable {
    public var projectRoot: URL
    public var runID: String
    public var runDirectory: URL
    public var packageStore: XcircuitePackageStore
    public var toolRegistry: ToolRegistry
    public var healthResults: [String: ToolHealthCheckResult]

    public init(
        projectRoot: URL,
        runID: String,
        runDirectory: URL,
        packageStore: XcircuitePackageStore,
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

    public func loadCancellationRequest() throws -> FlowRunCancellationRequest? {
        try FlowRunProgressStore(packageStore: packageStore).loadCancellationRequest(
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

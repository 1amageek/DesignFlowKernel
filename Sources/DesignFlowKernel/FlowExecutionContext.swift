import Foundation
import ToolQualification

public struct FlowExecutionContext: Sendable {
    public var projectRoot: URL
    public var runID: String
    public var runDirectory: URL
    public var infrastructure: any FlowRunInfrastructure
    public var toolRegistry: ToolRegistry
    public var healthResults: [String: ToolHealthCheckResult]

    public init(
        projectRoot: URL,
        runID: String,
        runDirectory: URL,
        infrastructure: any FlowRunInfrastructure,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult]
    ) {
        self.projectRoot = projectRoot
        self.runID = runID
        self.runDirectory = runDirectory
        self.infrastructure = infrastructure
        self.toolRegistry = toolRegistry
        self.healthResults = healthResults
    }

    public func loadCancellationRequest() async throws -> FlowRunCancellationRequest? {
        try await infrastructure.loadCancellationRequest(runID: runID)
    }

    public func checkCancellation() async throws {
        if let request = try await loadCancellationRequest() {
            throw FlowRunCancellationError.requested(request)
        }
    }
}

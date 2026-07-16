import ToolQualification

public struct FlowExecutionContext: Sendable {
    public var workspaceID: FlowWorkspaceID
    public var runID: String
    public var infrastructure: any FlowRunInfrastructure
    public var toolRegistry: ToolRegistry
    public var healthResults: [String: ToolHealthCheckResult]

    public init(
        workspaceID: FlowWorkspaceID,
        runID: String,
        infrastructure: any FlowRunInfrastructure,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult]
    ) {
        self.workspaceID = workspaceID
        self.runID = runID
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

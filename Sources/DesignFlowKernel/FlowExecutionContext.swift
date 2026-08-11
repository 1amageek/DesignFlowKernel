import ToolQualification

public struct FlowExecutionContext: Sendable {
    public var workspaceID: FlowWorkspaceID
    public var runID: String
    public var infrastructure: any FlowRunInfrastructure
    public var toolRegistry: ToolRegistry
    public var healthResults: [String: ToolHealthCheckResult]
    public var stageInputArtifacts: [FlowArtifactBinding]
    public var stageExecutionAttemptID: FlowStageExecutionAttemptID?

    public init(
        workspaceID: FlowWorkspaceID,
        runID: String,
        infrastructure: any FlowRunInfrastructure,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult],
        stageInputArtifacts: [FlowArtifactBinding] = [],
        stageExecutionAttemptID: FlowStageExecutionAttemptID? = nil
    ) {
        self.workspaceID = workspaceID
        self.runID = runID
        self.infrastructure = infrastructure
        self.toolRegistry = toolRegistry
        self.healthResults = healthResults
        self.stageInputArtifacts = stageInputArtifacts
        self.stageExecutionAttemptID = stageExecutionAttemptID
    }

    public func loadCancellationRequest() async throws -> FlowRunCancellationRequest? {
        try await infrastructure.loadCancellationRequest(runID: runID)
    }

    public func checkCancellation() async throws {
        if let request = try await loadCancellationRequest() {
            throw FlowRunCancellationError.requested(request)
        }
    }

    public func withStageInputArtifacts(
        _ artifacts: [FlowArtifactBinding]
    ) -> FlowExecutionContext {
        FlowExecutionContext(
            workspaceID: workspaceID,
            runID: runID,
            infrastructure: infrastructure,
            toolRegistry: toolRegistry,
            healthResults: healthResults,
            stageInputArtifacts: artifacts,
            stageExecutionAttemptID: stageExecutionAttemptID
        )
    }

    public func withStageExecutionAttemptID(
        _ attemptID: FlowStageExecutionAttemptID
    ) -> FlowExecutionContext {
        FlowExecutionContext(
            workspaceID: workspaceID,
            runID: runID,
            infrastructure: infrastructure,
            toolRegistry: toolRegistry,
            healthResults: healthResults,
            stageInputArtifacts: stageInputArtifacts,
            stageExecutionAttemptID: attemptID
        )
    }
}

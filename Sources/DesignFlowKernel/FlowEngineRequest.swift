import ToolQualification

/// Complete input required to execute a design flow through the Foundation
/// `Engine` contract. The operation itself remains Codable; this execution
/// envelope intentionally keeps runtime dependencies typed and in-memory.
public struct FlowEngineRequest: Sendable {
    public let operation: FlowOperationRequest
    public let toolRegistry: ToolRegistry
    public let healthResults: [String: ToolHealthCheckResult]
    public let executors: [any FlowStageExecutor]

    public init(
        operation: FlowOperationRequest,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult] = [:],
        executors: [any FlowStageExecutor]
    ) {
        self.operation = operation
        self.toolRegistry = toolRegistry
        self.healthResults = healthResults
        self.executors = executors
    }
}

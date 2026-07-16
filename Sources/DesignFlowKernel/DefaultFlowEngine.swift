import CircuiteFoundation

/// Default Foundation-compatible engine that delegates execution to the
/// existing flow orchestrator and preserves its trust-gate/resume semantics.
public struct DefaultFlowEngine: FlowEngine {
    private let orchestrator: DefaultFlowOrchestrator

    public init(orchestrator: DefaultFlowOrchestrator) {
        self.orchestrator = orchestrator
    }

    public func execute(_ request: FlowEngineRequest) async throws -> FlowRunResult {
        try await orchestrator.run(
            request: request.operation,
            toolRegistry: request.toolRegistry,
            healthResults: request.healthResults,
            executors: request.executors
        )
    }
}

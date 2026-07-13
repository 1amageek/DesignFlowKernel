import CircuiteFoundation

/// Foundation engine boundary for flow orchestration.
public protocol FlowEngine: Engine
where Request == FlowEngineRequest, Output == FlowRunResult {
}

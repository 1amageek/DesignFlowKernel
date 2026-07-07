import Foundation
import ToolQualification

public protocol FlowRunResuming: Sendable {
    func resumeRun(
        request: FlowRunResumeRequest,
        toolRegistry: ToolRegistry,
        healthResults: [String: ToolHealthCheckResult],
        executors: [any FlowStageExecutor]
    ) async throws -> FlowRunResumeResult
}

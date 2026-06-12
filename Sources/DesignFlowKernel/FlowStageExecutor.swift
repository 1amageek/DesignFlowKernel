import Foundation

public protocol FlowStageExecutor: Sendable {
    var stageID: String { get }
    var toolID: String { get }

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult
}

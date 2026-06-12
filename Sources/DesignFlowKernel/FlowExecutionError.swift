import Foundation

public enum FlowExecutionError: Error, LocalizedError, Equatable {
    case missingExecutor(String)
    case duplicateStageID(String)
    case duplicateExecutorStageID(String)
    case invalidExecutorToolID(stageID: String, toolID: String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutor(let stageID):
            "Missing flow stage executor: \(stageID)"
        case .duplicateStageID(let stageID):
            "Duplicate flow stage ID: \(stageID)"
        case .duplicateExecutorStageID(let stageID):
            "Duplicate flow stage executor ID: \(stageID)"
        case .invalidExecutorToolID(let stageID, let toolID):
            "Invalid executor tool ID for stage \(stageID): \(toolID)"
        }
    }
}

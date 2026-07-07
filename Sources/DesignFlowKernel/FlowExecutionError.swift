import Foundation

public enum FlowExecutionError: Error, LocalizedError, Equatable {
    case missingExecutor(String)
    case duplicateStageID(String)
    case duplicateExecutorStageID(String)
    case invalidExecutorToolID(stageID: String, toolID: String)
    case invalidRetryPolicy(stageID: String, maxAttempts: Int)
    case duplicateRunID(String)
    case existingRunPlanMismatch(String)

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
        case .invalidRetryPolicy(let stageID, let maxAttempts):
            "Invalid retry policy for stage \(stageID): maxAttempts must be at least 1, got \(maxAttempts)"
        case .duplicateRunID(let runID):
            "Run directory already exists for run ID: \(runID)"
        case .existingRunPlanMismatch(let runID):
            "Existing run plan does not match the requested run: \(runID)"
        }
    }
}

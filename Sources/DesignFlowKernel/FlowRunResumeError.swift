import Foundation

public enum FlowRunResumeError: Error, Equatable, LocalizedError {
    case missingPlan(String)
    case missingPlanReference(String)
    case invalidPlanReference(runID: String, status: XcircuiteFileReferenceIntegrityStatus)
    case runStatusNotResumable(runID: String, status: FlowRunStatus)

    public var errorDescription: String? {
        switch self {
        case .missingPlan(let runID):
            "Run cannot be resumed because plan.json is missing: \(runID)"
        case .missingPlanReference(let runID):
            "Run cannot be resumed because manifest.json does not record plan.json integrity: \(runID)"
        case .invalidPlanReference(let runID, let status):
            "Run cannot be resumed because plan.json integrity verification failed for \(runID): \(status.rawValue)"
        case .runStatusNotResumable(let runID, let status):
            "Run cannot be resumed from status \(status.rawValue): \(runID)"
        }
    }
}

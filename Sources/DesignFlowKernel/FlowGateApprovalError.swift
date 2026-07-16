import Foundation

public enum FlowGateApprovalError: Error, Equatable, LocalizedError {
    case stageNotFound(String)
    case approvalGateNotFound(String)
    case evidenceArtifactNotFound(String)
    case waiverReasonRequired
    case approvalRecordNotPersisted(runID: String, stageID: String)

    public var errorDescription: String? {
        switch self {
        case .stageNotFound(let stageID):
            "Stage not found in run ledger: \(stageID)"
        case .approvalGateNotFound(let stageID):
            "Stage does not expose an approval gate: \(stageID)"
        case .evidenceArtifactNotFound(let path):
            "Approval evidence artifact is not registered: \(path)"
        case .waiverReasonRequired:
            "A waiver requires a non-empty review note."
        case .approvalRecordNotPersisted(let runID, let stageID):
            "Approval record was not persisted for stage \(stageID) in run \(runID)"
        }
    }
}

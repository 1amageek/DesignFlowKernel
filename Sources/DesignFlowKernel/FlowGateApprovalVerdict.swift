import Foundation

public enum FlowGateApprovalVerdict: String, Sendable, Hashable, Codable {
    case approved
    case waived
    case rejected

    var approvalRecordVerdict: FlowApprovalRecord.Verdict {
        switch self {
        case .approved:
            .approved
        case .waived:
            .waived
        case .rejected:
            .rejected
        }
    }
}

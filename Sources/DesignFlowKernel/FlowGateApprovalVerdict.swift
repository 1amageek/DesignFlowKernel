import Foundation
import XcircuitePackage

public enum FlowGateApprovalVerdict: String, Sendable, Hashable, Codable {
    case approved
    case rejected

    var approvalRecordVerdict: XcircuiteApprovalRecord.Verdict {
        switch self {
        case .approved:
            .approved
        case .rejected:
            .rejected
        }
    }
}

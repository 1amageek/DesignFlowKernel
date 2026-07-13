import Foundation

public struct FlowGateApprovalResult: Sendable, Hashable, Codable {
    public var approval: XcircuiteApprovalRecord
    public var summary: FlowRunLedgerSummary

    public init(
        approval: XcircuiteApprovalRecord,
        summary: FlowRunLedgerSummary
    ) {
        self.approval = approval
        self.summary = summary
    }
}

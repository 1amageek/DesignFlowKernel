import Foundation

public struct FlowGateApprovalResult: Sendable, Hashable, Codable {
    public var approval: FlowApprovalRecord
    public var summary: FlowRunLedgerSummary

    public init(
        approval: FlowApprovalRecord,
        summary: FlowRunLedgerSummary
    ) {
        self.approval = approval
        self.summary = summary
    }
}

import Foundation

public protocol FlowGateApprovalRecording: Sendable {
    func recordApproval(_ request: FlowGateApprovalRequest) throws -> FlowGateApprovalResult
}

import Foundation

public protocol FlowGateApprovalRecording: Sendable {
    func recordApproval(_ request: FlowGateApprovalRequest) async throws -> FlowGateApprovalResult
}

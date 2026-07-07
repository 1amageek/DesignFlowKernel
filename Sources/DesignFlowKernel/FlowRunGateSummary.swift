import Foundation

public struct FlowRunGateSummary: Sendable, Hashable, Codable {
    public var gateID: String
    public var status: FlowGateStatus
    public var diagnosticCodes: [String]

    public init(
        gateID: String,
        status: FlowGateStatus,
        diagnosticCodes: [String] = []
    ) {
        self.gateID = gateID
        self.status = status
        self.diagnosticCodes = diagnosticCodes
    }
}

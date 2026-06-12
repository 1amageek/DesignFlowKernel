import Foundation

public struct FlowGateResult: Sendable, Hashable, Codable {
    public var gateID: String
    public var status: FlowGateStatus
    public var diagnostics: [FlowDiagnostic]

    public init(
        gateID: String,
        status: FlowGateStatus,
        diagnostics: [FlowDiagnostic] = []
    ) {
        self.gateID = gateID
        self.status = status
        self.diagnostics = diagnostics
    }
}

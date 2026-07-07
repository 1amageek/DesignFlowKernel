import Foundation

public protocol FlowRunDecisionPacketValidating: Sendable {
    func validateDecisionPacket(
        runID: String,
        projectRoot: URL
    ) throws -> FlowRunDecisionPacketValidationResult
}

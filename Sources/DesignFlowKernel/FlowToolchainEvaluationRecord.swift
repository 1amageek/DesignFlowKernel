import Foundation
import ToolQualification

public struct FlowToolchainEvaluationRecord: Sendable, Hashable, Codable {
    public var descriptor: ToolDescriptor
    public var decision: ToolTrustDecision
    public var health: ToolHealthCheckResult?

    public init(
        descriptor: ToolDescriptor,
        decision: ToolTrustDecision,
        health: ToolHealthCheckResult? = nil
    ) {
        self.descriptor = descriptor
        self.decision = decision
        self.health = health
    }
}

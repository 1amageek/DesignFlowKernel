import Foundation
import ToolQualification

public struct FlowToolchainStageRecord: Sendable, Hashable, Codable {
    public var stageID: String
    public var executorToolID: String
    public var requiredTool: ToolTrustRequirement?
    public var selectedToolID: String?
    public var selectedDescriptor: ToolDescriptor?
    public var selectedDecision: ToolTrustDecision?
    public var selectedHealth: ToolHealthCheckResult?
    public var evaluations: [FlowToolchainEvaluationRecord]

    public init(
        stageID: String,
        executorToolID: String,
        requiredTool: ToolTrustRequirement? = nil,
        selectedToolID: String? = nil,
        selectedDescriptor: ToolDescriptor? = nil,
        selectedDecision: ToolTrustDecision? = nil,
        selectedHealth: ToolHealthCheckResult? = nil,
        evaluations: [FlowToolchainEvaluationRecord] = []
    ) {
        self.stageID = stageID
        self.executorToolID = executorToolID
        self.requiredTool = requiredTool
        self.selectedToolID = selectedToolID
        self.selectedDescriptor = selectedDescriptor
        self.selectedDecision = selectedDecision
        self.selectedHealth = selectedHealth
        self.evaluations = evaluations
    }
}

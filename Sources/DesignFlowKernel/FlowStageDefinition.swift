import Foundation
import ToolQualification

public struct FlowStageDefinition: Sendable, Hashable, Codable {
    public var stageID: String
    public var displayName: String
    public var requiredTool: ToolTrustRequirement?
    /// When true the stage carries an additional "approval" gate judged
    /// from the run's `approvals/{stageID}.json` record: approved →
    /// passed, rejected → failed, absent → incomplete and the run
    /// blocks. Re-running the same runID after the cockpit records the
    /// decision resumes the flow.
    public var requiresApproval: Bool
    public var retryPolicy: FlowStageRetryPolicy

    public init(
        stageID: String,
        displayName: String,
        requiredTool: ToolTrustRequirement? = nil,
        requiresApproval: Bool = false,
        retryPolicy: FlowStageRetryPolicy = .disabled
    ) {
        self.stageID = stageID
        self.displayName = displayName
        self.requiredTool = requiredTool
        self.requiresApproval = requiresApproval
        self.retryPolicy = retryPolicy
    }

}

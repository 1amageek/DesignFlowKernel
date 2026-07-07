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

    private enum CodingKeys: String, CodingKey {
        case stageID
        case displayName
        case requiredTool
        case requiresApproval
        case retryPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stageID = try container.decode(String.self, forKey: .stageID)
        displayName = try container.decode(String.self, forKey: .displayName)
        requiredTool = try container.decodeIfPresent(ToolTrustRequirement.self, forKey: .requiredTool)
        // Definitions written before the approval gate existed decode
        // as not requiring one.
        requiresApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? false
        retryPolicy = try container.decodeIfPresent(
            FlowStageRetryPolicy.self,
            forKey: .retryPolicy
        ) ?? .disabled
    }
}

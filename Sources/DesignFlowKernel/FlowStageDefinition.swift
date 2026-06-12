import Foundation
import ToolQualification

public struct FlowStageDefinition: Sendable, Hashable, Codable {
    public var stageID: String
    public var displayName: String
    public var requiredTool: ToolTrustRequirement?

    public init(
        stageID: String,
        displayName: String,
        requiredTool: ToolTrustRequirement? = nil
    ) {
        self.stageID = stageID
        self.displayName = displayName
        self.requiredTool = requiredTool
    }
}

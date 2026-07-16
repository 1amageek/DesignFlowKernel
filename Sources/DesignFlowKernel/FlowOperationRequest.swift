import Foundation

public struct FlowOperationRequest: Sendable, Hashable, Codable {
    public var workspaceID: FlowWorkspaceID
    public var runID: String
    public var intent: String
    public var actor: FlowRunActor
    public var toolchainProfile: FlowToolchainProfileRecord?
    public var stages: [FlowStageDefinition]
    public var allowExistingRun: Bool

    public init(
        workspaceID: FlowWorkspaceID,
        runID: String,
        intent: String,
        actor: FlowRunActor = FlowRunActor(
            kind: .system,
            identifier: "design-flow-kernel"
        ),
        toolchainProfile: FlowToolchainProfileRecord? = nil,
        stages: [FlowStageDefinition],
        allowExistingRun: Bool = false
    ) {
        self.workspaceID = workspaceID
        self.runID = runID
        self.intent = intent
        self.actor = actor
        self.toolchainProfile = toolchainProfile
        self.stages = stages
        self.allowExistingRun = allowExistingRun
    }

}

import Foundation

public struct FlowRunPlan: Sendable, Hashable, Codable {
    @FlowSchemaVersion2 public var schemaVersion: Int
    public var runID: String
    public var intent: String
    public var toolchainProfile: FlowToolchainProfileRecord?
    public var stages: [FlowStageDefinition]
    public var stageInputs: [FlowStageInputBinding]

    public init(
        schemaVersion: Int = 2,
        runID: String,
        intent: String,
        toolchainProfile: FlowToolchainProfileRecord? = nil,
        stages: [FlowStageDefinition],
        stageInputs: [FlowStageInputBinding] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.intent = intent
        self.toolchainProfile = toolchainProfile
        self.stages = stages
        self.stageInputs = stageInputs
    }

    public func makeRequest(workspaceID: FlowWorkspaceID) -> FlowOperationRequest {
        FlowOperationRequest(
            workspaceID: workspaceID,
            runID: runID,
            intent: intent,
            toolchainProfile: toolchainProfile,
            stages: stages,
            stageInputs: stageInputs
        )
    }
}

import Foundation

public struct FlowRunPlan: Sendable, Hashable, Codable {
    @FlowSchemaVersion1 public var schemaVersion: Int
    public var runID: String
    public var intent: String
    public var toolchainProfile: FlowToolchainProfileRecord?
    public var stages: [FlowStageDefinition]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        intent: String,
        toolchainProfile: FlowToolchainProfileRecord? = nil,
        stages: [FlowStageDefinition]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.intent = intent
        self.toolchainProfile = toolchainProfile
        self.stages = stages
    }

    public func makeRequest(projectRoot: URL) -> FlowOperationRequest {
        FlowOperationRequest(
            projectRoot: projectRoot,
            runID: runID,
            intent: intent,
            toolchainProfile: toolchainProfile,
            stages: stages
        )
    }
}

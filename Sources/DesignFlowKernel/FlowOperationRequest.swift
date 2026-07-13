import Foundation

public struct FlowOperationRequest: Sendable, Hashable, Codable {
    public var projectRoot: URL
    public var runID: String
    public var intent: String
    public var actor: XcircuiteRunActionActor
    public var toolchainProfile: FlowToolchainProfileRecord?
    public var stages: [FlowStageDefinition]
    public var allowExistingRunDirectory: Bool

    public init(
        projectRoot: URL,
        runID: String,
        intent: String,
        actor: XcircuiteRunActionActor = XcircuiteRunActionActor(
            kind: .system,
            identifier: "design-flow-kernel"
        ),
        toolchainProfile: FlowToolchainProfileRecord? = nil,
        stages: [FlowStageDefinition],
        allowExistingRunDirectory: Bool = false
    ) {
        self.projectRoot = projectRoot
        self.runID = runID
        self.intent = intent
        self.actor = actor
        self.toolchainProfile = toolchainProfile
        self.stages = stages
        self.allowExistingRunDirectory = allowExistingRunDirectory
    }

}

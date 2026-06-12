import Foundation

public struct FlowOperationRequest: Sendable, Hashable, Codable {
    public var projectRoot: URL
    public var runID: String
    public var intent: String
    public var stages: [FlowStageDefinition]

    public init(
        projectRoot: URL,
        runID: String,
        intent: String,
        stages: [FlowStageDefinition]
    ) {
        self.projectRoot = projectRoot
        self.runID = runID
        self.intent = intent
        self.stages = stages
    }
}

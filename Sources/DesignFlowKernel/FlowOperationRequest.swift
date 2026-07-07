import Foundation

public struct FlowOperationRequest: Sendable, Hashable, Codable {
    public var projectRoot: URL
    public var runID: String
    public var intent: String
    public var toolchainProfile: FlowToolchainProfileRecord?
    public var stages: [FlowStageDefinition]
    public var allowExistingRunDirectory: Bool

    public init(
        projectRoot: URL,
        runID: String,
        intent: String,
        toolchainProfile: FlowToolchainProfileRecord? = nil,
        stages: [FlowStageDefinition],
        allowExistingRunDirectory: Bool = false
    ) {
        self.projectRoot = projectRoot
        self.runID = runID
        self.intent = intent
        self.toolchainProfile = toolchainProfile
        self.stages = stages
        self.allowExistingRunDirectory = allowExistingRunDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case projectRoot
        case runID
        case intent
        case toolchainProfile
        case stages
        case allowExistingRunDirectory
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectRoot = try container.decode(URL.self, forKey: .projectRoot)
        runID = try container.decode(String.self, forKey: .runID)
        intent = try container.decode(String.self, forKey: .intent)
        toolchainProfile = try container.decodeIfPresent(
            FlowToolchainProfileRecord.self,
            forKey: .toolchainProfile
        )
        stages = try container.decode([FlowStageDefinition].self, forKey: .stages)
        allowExistingRunDirectory = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowExistingRunDirectory
        ) ?? false
    }
}

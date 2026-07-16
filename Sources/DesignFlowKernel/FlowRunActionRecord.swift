import CircuiteFoundation
import Foundation

public struct FlowRunActionRecord: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var actionID: String
    public var runID: String
    public var stageID: String?
    public var actor: FlowRunActor
    public var actionKind: String
    public var status: FlowRunActionStatus
    public var inputs: [ArtifactReference]
    public var outputs: [ArtifactReference]
    public var diagnostics: [FlowRunDiagnostic]
    public var context: FlowRunActionContext
    public var createdAt: Date

    public init(
        actionID: String,
        runID: String,
        stageID: String? = nil,
        actor: FlowRunActor,
        actionKind: String,
        status: FlowRunActionStatus,
        inputs: [ArtifactReference] = [],
        outputs: [ArtifactReference] = [],
        diagnostics: [FlowRunDiagnostic] = [],
        context: FlowRunActionContext = FlowRunActionContext(),
        createdAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.actionID = actionID
        self.runID = runID
        self.stageID = stageID
        self.actor = actor
        self.actionKind = actionKind
        self.status = status
        self.inputs = inputs
        self.outputs = outputs
        self.diagnostics = diagnostics
        self.context = context
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case actionID
        case runID
        case stageID
        case actor
        case actionKind
        case status
        case inputs
        case outputs
        case diagnostics
        case context
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected run action schema version \(Self.currentSchemaVersion)."
            )
        }
        self.actionID = try container.decode(String.self, forKey: .actionID)
        self.runID = try container.decode(String.self, forKey: .runID)
        self.stageID = try container.decodeIfPresent(String.self, forKey: .stageID)
        self.actor = try container.decode(FlowRunActor.self, forKey: .actor)
        self.actionKind = try container.decode(String.self, forKey: .actionKind)
        self.status = try container.decode(FlowRunActionStatus.self, forKey: .status)
        self.inputs = try container.decode(
            [ArtifactReference].self,
            forKey: .inputs
        )
        self.outputs = try container.decode(
            [ArtifactReference].self,
            forKey: .outputs
        )
        self.diagnostics = try container.decode(
            [FlowRunDiagnostic].self,
            forKey: .diagnostics
        )
        self.context = try container.decode(FlowRunActionContext.self, forKey: .context)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

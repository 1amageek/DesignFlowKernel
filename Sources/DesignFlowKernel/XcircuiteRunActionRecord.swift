import Foundation

public struct XcircuiteRunActionRecord: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var actionID: String
    public var runID: String
    public var stageID: String?
    public var actor: XcircuiteRunActionActor
    public var actionKind: String
    public var status: XcircuiteRunActionStatus
    public var inputs: [XcircuiteFileReference]
    public var outputs: [XcircuiteFileReference]
    public var diagnostics: [XcircuiteRunActionDiagnostic]
    public var metadata: [String: XcircuiteJSONValue]
    public var createdAt: Date

    public init(
        actionID: String,
        runID: String,
        stageID: String? = nil,
        actor: XcircuiteRunActionActor,
        actionKind: String,
        status: XcircuiteRunActionStatus,
        inputs: [XcircuiteFileReference] = [],
        outputs: [XcircuiteFileReference] = [],
        diagnostics: [XcircuiteRunActionDiagnostic] = [],
        metadata: [String: XcircuiteJSONValue] = [:],
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
        self.metadata = metadata
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
        case metadata
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
        self.actor = try container.decode(XcircuiteRunActionActor.self, forKey: .actor)
        self.actionKind = try container.decode(String.self, forKey: .actionKind)
        self.status = try container.decode(XcircuiteRunActionStatus.self, forKey: .status)
        self.inputs = try container.decode(
            [XcircuiteFileReference].self,
            forKey: .inputs
        )
        self.outputs = try container.decode(
            [XcircuiteFileReference].self,
            forKey: .outputs
        )
        self.diagnostics = try container.decode(
            [XcircuiteRunActionDiagnostic].self,
            forKey: .diagnostics
        )
        self.metadata = try container.decode(
            [String: XcircuiteJSONValue].self,
            forKey: .metadata
        )
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

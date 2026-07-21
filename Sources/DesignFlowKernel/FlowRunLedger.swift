import CircuiteFoundation
import Foundation

public struct FlowRunLedger: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 3

    public var runID: String
    public var runManifest: FlowRunManifest
    public var plan: FlowRunPlan?
    public var stages: [FlowStageResult]
    public var toolchain: FlowToolchainManifest?
    public var designDiff: DesignDiff?
    public var progressEvents: [FlowRunProgressEvent]
    public var cancellationRequest: FlowRunCancellationRequest?
    public var evidence: EvidenceManifest?
    public var artifacts: [ArtifactReference]
    public var actions: [FlowRunActionRecord]
    public var suggestedActionSelections: [FlowRunSuggestedActionSelection]
    public var approvals: [FlowApprovalRecord]

    public init(
        runID: String,
        runManifest: FlowRunManifest,
        plan: FlowRunPlan? = nil,
        stages: [FlowStageResult],
        toolchain: FlowToolchainManifest? = nil,
        designDiff: DesignDiff? = nil,
        progressEvents: [FlowRunProgressEvent] = [],
        cancellationRequest: FlowRunCancellationRequest? = nil,
        evidence: EvidenceManifest? = nil,
        artifacts: [ArtifactReference] = [],
        actions: [FlowRunActionRecord] = [],
        suggestedActionSelections: [FlowRunSuggestedActionSelection] = [],
        approvals: [FlowApprovalRecord] = []
    ) {
        self.runID = runID
        self.runManifest = runManifest
        self.plan = plan
        self.stages = stages
        self.toolchain = toolchain
        self.designDiff = designDiff
        self.progressEvents = progressEvents
        self.cancellationRequest = cancellationRequest
        self.evidence = evidence
        self.artifacts = artifacts
        self.actions = actions
        self.suggestedActionSelections = suggestedActionSelections
        self.approvals = approvals
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case runManifest
        case plan
        case stages
        case toolchain
        case designDiff
        case progressEvents
        case cancellationRequest
        case evidence
        case artifacts
        case actions
        case suggestedActionSelections
        case approvals
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported flow run ledger schema: \(schemaVersion)."
            )
        }
        runID = try container.decode(String.self, forKey: .runID)
        runManifest = try container.decode(FlowRunManifest.self, forKey: .runManifest)
        plan = try container.decodeIfPresent(FlowRunPlan.self, forKey: .plan)
        stages = try container.decode([FlowStageResult].self, forKey: .stages)
        toolchain = try container.decodeIfPresent(FlowToolchainManifest.self, forKey: .toolchain)
        designDiff = try container.decodeIfPresent(DesignDiff.self, forKey: .designDiff)
        progressEvents = try container.decode([FlowRunProgressEvent].self, forKey: .progressEvents)
        cancellationRequest = try container.decodeIfPresent(
            FlowRunCancellationRequest.self,
            forKey: .cancellationRequest
        )
        evidence = try container.decodeIfPresent(EvidenceManifest.self, forKey: .evidence)
        artifacts = try container.decode([ArtifactReference].self, forKey: .artifacts)
        actions = try container.decode([FlowRunActionRecord].self, forKey: .actions)
        suggestedActionSelections = try container.decode(
            [FlowRunSuggestedActionSelection].self,
            forKey: .suggestedActionSelections
        )
        approvals = try container.decode([FlowApprovalRecord].self, forKey: .approvals)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(runID, forKey: .runID)
        try container.encode(runManifest, forKey: .runManifest)
        try container.encodeIfPresent(plan, forKey: .plan)
        try container.encode(stages, forKey: .stages)
        try container.encodeIfPresent(toolchain, forKey: .toolchain)
        try container.encodeIfPresent(designDiff, forKey: .designDiff)
        try container.encode(progressEvents, forKey: .progressEvents)
        try container.encodeIfPresent(cancellationRequest, forKey: .cancellationRequest)
        try container.encodeIfPresent(evidence, forKey: .evidence)
        try container.encode(artifacts, forKey: .artifacts)
        try container.encode(actions, forKey: .actions)
        try container.encode(suggestedActionSelections, forKey: .suggestedActionSelections)
        try container.encode(approvals, forKey: .approvals)
    }

}

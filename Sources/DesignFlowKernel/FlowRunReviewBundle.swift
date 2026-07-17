import Foundation

public struct FlowRunReviewBundle: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 3

    public struct CoverageRef: Sendable, Hashable, Codable {
        public var domain: String
        public var role: String
        public var stageID: String?
        public var artifactID: String?
        public var path: String?
        public var integrityStatus: FlowRunReviewArtifactIntegrityStatus?
        public var reviewItemIDs: [String]
        public var decisionActionIDs: [String]

        public init(
            domain: String,
            role: String,
            stageID: String? = nil,
            artifactID: String? = nil,
            path: String? = nil,
            integrityStatus: FlowRunReviewArtifactIntegrityStatus? = nil,
            reviewItemIDs: [String] = [],
            decisionActionIDs: [String] = []
        ) {
            self.domain = domain
            self.role = role
            self.stageID = stageID
            self.artifactID = artifactID
            self.path = path
            self.integrityStatus = integrityStatus
            self.reviewItemIDs = reviewItemIDs
            self.decisionActionIDs = decisionActionIDs
        }
    }

    public let schemaVersion: Int
    public var runID: String
    public var status: FlowRunStatus
    public var summary: FlowRunLedgerSummary
    public var reviewItems: [FlowRunReviewItem]
    public var artifacts: [FlowRunReviewArtifact]
    public var approvals: [FlowApprovalRecord]
    public var decisionActions: [FlowRunReviewDecision]?
    public var coverageRefs: [CoverageRef]?
    public var agentLoopSnapshot: FlowAgentLoopSnapshot?
    public var runGuardVerdict: FlowRunGuardVerdict?
    public var crossArtifactEvaluation: FlowCrossArtifactEvaluation?

    public init(
        runID: String,
        status: FlowRunStatus,
        summary: FlowRunLedgerSummary,
        reviewItems: [FlowRunReviewItem] = [],
        artifacts: [FlowRunReviewArtifact] = [],
        approvals: [FlowApprovalRecord] = [],
        decisionActions: [FlowRunReviewDecision]? = nil,
        coverageRefs: [CoverageRef]? = nil,
        agentLoopSnapshot: FlowAgentLoopSnapshot? = nil,
        runGuardVerdict: FlowRunGuardVerdict? = nil,
        crossArtifactEvaluation: FlowCrossArtifactEvaluation? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.status = status
        self.summary = summary
        self.reviewItems = reviewItems
        self.artifacts = artifacts
        self.approvals = approvals
        self.decisionActions = decisionActions
        self.coverageRefs = coverageRefs
        self.agentLoopSnapshot = agentLoopSnapshot
        self.runGuardVerdict = runGuardVerdict
        self.crossArtifactEvaluation = crossArtifactEvaluation
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case status
        case summary
        case reviewItems
        case artifacts
        case approvals
        case decisionActions
        case coverageRefs
        case agentLoopSnapshot
        case runGuardVerdict
        case crossArtifactEvaluation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected review bundle schema version \(Self.currentSchemaVersion)."
            )
        }
        runID = try container.decode(String.self, forKey: .runID)
        status = try container.decode(FlowRunStatus.self, forKey: .status)
        summary = try container.decode(FlowRunLedgerSummary.self, forKey: .summary)
        reviewItems = try container.decode([FlowRunReviewItem].self, forKey: .reviewItems)
        artifacts = try container.decode([FlowRunReviewArtifact].self, forKey: .artifacts)
        approvals = try container.decode([FlowApprovalRecord].self, forKey: .approvals)
        decisionActions = try container.decodeIfPresent([FlowRunReviewDecision].self, forKey: .decisionActions)
        coverageRefs = try container.decodeIfPresent([CoverageRef].self, forKey: .coverageRefs)
        agentLoopSnapshot = try container.decodeIfPresent(FlowAgentLoopSnapshot.self, forKey: .agentLoopSnapshot)
        runGuardVerdict = try container.decodeIfPresent(FlowRunGuardVerdict.self, forKey: .runGuardVerdict)
        crossArtifactEvaluation = try container.decodeIfPresent(
            FlowCrossArtifactEvaluation.self,
            forKey: .crossArtifactEvaluation
        )
    }
}

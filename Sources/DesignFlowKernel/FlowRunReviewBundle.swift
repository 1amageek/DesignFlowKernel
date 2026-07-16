import Foundation

public struct FlowRunReviewBundle: Sendable, Hashable, Codable {
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

    @FlowSchemaVersion2 public var schemaVersion: Int
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
        schemaVersion: Int = 2,
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
        self.schemaVersion = schemaVersion
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
}

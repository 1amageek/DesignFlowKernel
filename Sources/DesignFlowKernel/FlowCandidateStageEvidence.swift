import CircuiteFoundation

public struct FlowCandidateStageEvidence: Sendable, Hashable, Codable {
    public let stageID: String
    public let candidateRevision: DesignRevisionReference
    public let semanticGraphDigest: ContentDigest
    public let result: ArtifactReference
    public let rawEvidence: [ArtifactReference]
    public let status: FlowStageStatus

    public init(
        stageID: String,
        candidateRevision: DesignRevisionReference,
        semanticGraphDigest: ContentDigest,
        result: ArtifactReference,
        rawEvidence: [ArtifactReference],
        status: FlowStageStatus
    ) {
        self.stageID = stageID
        self.candidateRevision = candidateRevision
        self.semanticGraphDigest = semanticGraphDigest
        self.result = result
        self.rawEvidence = rawEvidence
        self.status = status
    }
}

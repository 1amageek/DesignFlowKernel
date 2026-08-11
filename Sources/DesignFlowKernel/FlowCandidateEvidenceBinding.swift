import CircuiteFoundation
import CircuiteFoundationCrypto

public struct FlowCandidateEvidenceBinding: Sendable, Hashable, Codable {
    public let runID: String
    public let baseRevision: DesignRevisionReference
    public let candidateRevision: DesignRevisionReference
    public let semanticGraphDigest: ContentDigest
    public let resolutionEvidenceDigest: ContentDigest
    public let mutationPlanDigest: ContentDigest
    public let commitReceipt: ArtifactReference
    public let stageEvidence: [FlowCandidateStageEvidence]
    public let bindingDigest: ContentDigest

    public init(
        runID: String,
        baseRevision: DesignRevisionReference,
        candidateRevision: DesignRevisionReference,
        semanticGraphDigest: ContentDigest,
        resolutionEvidenceDigest: ContentDigest,
        mutationPlanDigest: ContentDigest,
        commitReceipt: ArtifactReference,
        stageEvidence: [FlowCandidateStageEvidence],
        bindingDigest: ContentDigest
    ) {
        self.runID = runID
        self.baseRevision = baseRevision
        self.candidateRevision = candidateRevision
        self.semanticGraphDigest = semanticGraphDigest
        self.resolutionEvidenceDigest = resolutionEvidenceDigest
        self.mutationPlanDigest = mutationPlanDigest
        self.commitReceipt = commitReceipt
        self.stageEvidence = stageEvidence
        self.bindingDigest = bindingDigest
    }

    public static func contentAddressed(
        runID: String,
        baseRevision: DesignRevisionReference,
        candidateRevision: DesignRevisionReference,
        semanticGraphDigest: ContentDigest,
        resolutionEvidenceDigest: ContentDigest,
        mutationPlanDigest: ContentDigest,
        commitReceipt: ArtifactReference,
        stageEvidence: [FlowCandidateStageEvidence],
        using digester: any ContentDigesting = SHA256ContentDigester()
    ) throws -> Self {
        let bindingDigest = try FlowCandidateEvidenceBindingDigest.make(
            runID: runID,
            baseRevision: baseRevision,
            candidateRevision: candidateRevision,
            semanticGraphDigest: semanticGraphDigest,
            resolutionEvidenceDigest: resolutionEvidenceDigest,
            mutationPlanDigest: mutationPlanDigest,
            commitReceipt: commitReceipt,
            stageEvidence: stageEvidence,
            using: digester
        )
        return Self(
            runID: runID,
            baseRevision: baseRevision,
            candidateRevision: candidateRevision,
            semanticGraphDigest: semanticGraphDigest,
            resolutionEvidenceDigest: resolutionEvidenceDigest,
            mutationPlanDigest: mutationPlanDigest,
            commitReceipt: commitReceipt,
            stageEvidence: stageEvidence,
            bindingDigest: bindingDigest
        )
    }
}

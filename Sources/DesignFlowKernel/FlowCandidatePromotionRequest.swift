import CircuiteFoundation

public struct FlowCandidatePromotionRequest: Sendable, Hashable, Codable {
    public let evidenceBinding: FlowCandidateEvidenceBinding
    public let evidenceBindingArtifact: FlowArtifactBinding
    public let designDiffArtifact: FlowArtifactBinding
    public let approvalArtifacts: [FlowArtifactBinding]
    public let targetReferenceName: String
    public let expectedGeneration: UInt64
    public let expectedRevision: DesignRevisionReference?

    public init(
        evidenceBinding: FlowCandidateEvidenceBinding,
        evidenceBindingArtifact: FlowArtifactBinding,
        designDiffArtifact: FlowArtifactBinding,
        approvalArtifacts: [FlowArtifactBinding],
        targetReferenceName: String,
        expectedGeneration: UInt64,
        expectedRevision: DesignRevisionReference?
    ) {
        self.evidenceBinding = evidenceBinding
        self.evidenceBindingArtifact = evidenceBindingArtifact
        self.designDiffArtifact = designDiffArtifact
        self.approvalArtifacts = approvalArtifacts
        self.targetReferenceName = targetReferenceName
        self.expectedGeneration = expectedGeneration
        self.expectedRevision = expectedRevision
    }
}

import CircuiteFoundation
import CircuiteFoundationCrypto

public struct FlowCandidateStageAttestation: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let runID: String
    public let stageID: String
    public let evidenceType: String
    public let candidateRevision: DesignRevisionReference
    public let semanticGraphDigest: ContentDigest
    public let commitReceipt: ArtifactReference
    public let result: ArtifactReference
    public let rawEvidence: [ArtifactReference]
    public let inputArtifacts: [ArtifactReference]
    public let status: FlowStageStatus
    public let attestationDigest: ContentDigest

    public init(
        runID: String,
        stageID: String,
        evidenceType: String,
        candidateRevision: DesignRevisionReference,
        semanticGraphDigest: ContentDigest,
        commitReceipt: ArtifactReference,
        result: ArtifactReference,
        rawEvidence: [ArtifactReference],
        inputArtifacts: [ArtifactReference],
        status: FlowStageStatus,
        attestationDigest: ContentDigest
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.stageID = stageID
        self.evidenceType = evidenceType
        self.candidateRevision = candidateRevision
        self.semanticGraphDigest = semanticGraphDigest
        self.commitReceipt = commitReceipt
        self.result = result
        self.rawEvidence = rawEvidence
        self.inputArtifacts = inputArtifacts
        self.status = status
        self.attestationDigest = attestationDigest
    }

    public static func contentAddressed(
        runID: String,
        stageID: String,
        evidenceType: String,
        candidateRevision: DesignRevisionReference,
        semanticGraphDigest: ContentDigest,
        commitReceipt: ArtifactReference,
        result: ArtifactReference,
        rawEvidence: [ArtifactReference],
        inputArtifacts: [ArtifactReference],
        status: FlowStageStatus,
        using digester: any ContentDigesting = SHA256ContentDigester()
    ) throws -> Self {
        let digest = try FlowCandidateStageAttestationDigest.make(
            runID: runID,
            stageID: stageID,
            evidenceType: evidenceType,
            candidateRevision: candidateRevision,
            semanticGraphDigest: semanticGraphDigest,
            commitReceipt: commitReceipt,
            result: result,
            rawEvidence: rawEvidence,
            inputArtifacts: inputArtifacts,
            status: status,
            using: digester
        )
        return Self(
            runID: runID,
            stageID: stageID,
            evidenceType: evidenceType,
            candidateRevision: candidateRevision,
            semanticGraphDigest: semanticGraphDigest,
            commitReceipt: commitReceipt,
            result: result,
            rawEvidence: rawEvidence,
            inputArtifacts: inputArtifacts,
            status: status,
            attestationDigest: digest
        )
    }
}

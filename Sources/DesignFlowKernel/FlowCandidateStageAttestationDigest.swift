import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public enum FlowCandidateStageAttestationDigest {
    public static func make(
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
    ) throws -> ContentDigest {
        let projection = Projection(
            runID: runID,
            stageID: stageID,
            evidenceType: evidenceType,
            candidateRevision: candidateRevision,
            semanticGraphDigest: semanticGraphDigest,
            commitReceipt: commitReceipt,
            result: result,
            rawEvidence: rawEvidence.sorted(by: referenceOrder),
            inputArtifacts: inputArtifacts.sorted(by: referenceOrder),
            status: status
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try digester.digest(data: encoder.encode(projection))
    }

    private static func referenceOrder(
        _ lhs: ArtifactReference,
        _ rhs: ArtifactReference
    ) -> Bool {
        lhs.id.description < rhs.id.description
    }

    private struct Projection: Encodable {
        let runID: String
        let stageID: String
        let evidenceType: String
        let candidateRevision: DesignRevisionReference
        let semanticGraphDigest: ContentDigest
        let commitReceipt: ArtifactReference
        let result: ArtifactReference
        let rawEvidence: [ArtifactReference]
        let inputArtifacts: [ArtifactReference]
        let status: FlowStageStatus
    }
}

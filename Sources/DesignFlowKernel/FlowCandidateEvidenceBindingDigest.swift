import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public enum FlowCandidateEvidenceBindingDigest {
    public static func make(
        runID: String,
        baseRevision: DesignRevisionReference,
        candidateRevision: DesignRevisionReference,
        semanticGraphDigest: ContentDigest,
        resolutionEvidenceDigest: ContentDigest,
        mutationPlanDigest: ContentDigest,
        commitReceipt: ArtifactReference,
        stageEvidence: [FlowCandidateStageEvidence],
        using digester: any ContentDigesting = SHA256ContentDigester()
    ) throws -> ContentDigest {
        let normalizedStages = stageEvidence
            .map { evidence in
                FlowCandidateStageEvidence(
                    stageID: evidence.stageID,
                    candidateRevision: evidence.candidateRevision,
                    semanticGraphDigest: evidence.semanticGraphDigest,
                    result: evidence.result,
                    rawEvidence: evidence.rawEvidence.sorted {
                        $0.id.description < $1.id.description
                    },
                    status: evidence.status
                )
            }
            .sorted { $0.stageID < $1.stageID }
        let projection = Projection(
            runID: runID,
            baseRevision: baseRevision,
            candidateRevision: candidateRevision,
            semanticGraphDigest: semanticGraphDigest,
            resolutionEvidenceDigest: resolutionEvidenceDigest,
            mutationPlanDigest: mutationPlanDigest,
            commitReceipt: commitReceipt,
            stageEvidence: normalizedStages
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try digester.digest(data: encoder.encode(projection))
    }

    private struct Projection: Encodable {
        let runID: String
        let baseRevision: DesignRevisionReference
        let candidateRevision: DesignRevisionReference
        let semanticGraphDigest: ContentDigest
        let resolutionEvidenceDigest: ContentDigest
        let mutationPlanDigest: ContentDigest
        let commitReceipt: ArtifactReference
        let stageEvidence: [FlowCandidateStageEvidence]
    }
}

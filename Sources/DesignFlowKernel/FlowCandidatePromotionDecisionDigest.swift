import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public enum FlowCandidatePromotionDecisionDigest {
    public static func make(
        decisionID: String,
        runID: String,
        candidateRevision: DesignRevisionReference,
        semanticGraphDigest: ContentDigest,
        evidenceBindingDigest: ContentDigest,
        designDiff: ArtifactReference,
        verdict: FlowCandidatePromotionDecision.Verdict,
        reasonCodes: [String],
        approvals: [ArtifactReference],
        policyID: String,
        policyVersion: String,
        decidedAt: Date,
        using digester: any ContentDigesting = SHA256ContentDigester()
    ) throws -> ContentDigest {
        let projection = Projection(
            decisionID: decisionID,
            runID: runID,
            candidateRevision: candidateRevision,
            semanticGraphDigest: semanticGraphDigest,
            evidenceBindingDigest: evidenceBindingDigest,
            designDiff: designDiff,
            verdict: verdict,
            reasonCodes: reasonCodes.sorted(),
            approvals: approvals.sorted {
                $0.id.description < $1.id.description
            },
            policyID: policyID,
            policyVersion: policyVersion,
            decidedAt: decidedAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try digester.digest(data: encoder.encode(projection))
    }

    private struct Projection: Encodable {
        let decisionID: String
        let runID: String
        let candidateRevision: DesignRevisionReference
        let semanticGraphDigest: ContentDigest
        let evidenceBindingDigest: ContentDigest
        let designDiff: ArtifactReference
        let verdict: FlowCandidatePromotionDecision.Verdict
        let reasonCodes: [String]
        let approvals: [ArtifactReference]
        let policyID: String
        let policyVersion: String
        let decidedAt: Date
    }
}

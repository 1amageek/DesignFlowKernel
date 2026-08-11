import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public struct FlowCandidatePromotionDecision: Sendable, Hashable, Codable {
    public enum Verdict: String, Sendable, Hashable, Codable {
        case authorized
        case rejected
        case needsEvidence
    }

    public let decisionID: String
    public let runID: String
    public let candidateRevision: DesignRevisionReference
    public let semanticGraphDigest: ContentDigest
    public let evidenceBindingDigest: ContentDigest
    public let designDiff: ArtifactReference
    public let verdict: Verdict
    public let reasonCodes: [String]
    public let approvals: [ArtifactReference]
    public let policyID: String
    public let policyVersion: String
    public let decidedAt: Date
    public let decisionDigest: ContentDigest

    public init(
        decisionID: String,
        runID: String,
        candidateRevision: DesignRevisionReference,
        semanticGraphDigest: ContentDigest,
        evidenceBindingDigest: ContentDigest,
        designDiff: ArtifactReference,
        verdict: Verdict,
        reasonCodes: [String],
        approvals: [ArtifactReference],
        policyID: String,
        policyVersion: String,
        decidedAt: Date,
        decisionDigest: ContentDigest
    ) {
        self.decisionID = decisionID
        self.runID = runID
        self.candidateRevision = candidateRevision
        self.semanticGraphDigest = semanticGraphDigest
        self.evidenceBindingDigest = evidenceBindingDigest
        self.designDiff = designDiff
        self.verdict = verdict
        self.reasonCodes = reasonCodes
        self.approvals = approvals
        self.policyID = policyID
        self.policyVersion = policyVersion
        self.decidedAt = decidedAt
        self.decisionDigest = decisionDigest
    }

    public static func contentAddressed(
        decisionID: String,
        runID: String,
        candidateRevision: DesignRevisionReference,
        semanticGraphDigest: ContentDigest,
        evidenceBindingDigest: ContentDigest,
        designDiff: ArtifactReference,
        verdict: Verdict,
        reasonCodes: [String],
        approvals: [ArtifactReference],
        policyID: String,
        policyVersion: String,
        decidedAt: Date,
        using digester: any ContentDigesting = SHA256ContentDigester()
    ) throws -> Self {
        let normalizedReasonCodes = reasonCodes.sorted()
        let normalizedApprovals = approvals.sorted {
            $0.id.description < $1.id.description
        }
        let digest = try FlowCandidatePromotionDecisionDigest.make(
            decisionID: decisionID,
            runID: runID,
            candidateRevision: candidateRevision,
            semanticGraphDigest: semanticGraphDigest,
            evidenceBindingDigest: evidenceBindingDigest,
            designDiff: designDiff,
            verdict: verdict,
            reasonCodes: normalizedReasonCodes,
            approvals: normalizedApprovals,
            policyID: policyID,
            policyVersion: policyVersion,
            decidedAt: decidedAt,
            using: digester
        )
        return Self(
            decisionID: decisionID,
            runID: runID,
            candidateRevision: candidateRevision,
            semanticGraphDigest: semanticGraphDigest,
            evidenceBindingDigest: evidenceBindingDigest,
            designDiff: designDiff,
            verdict: verdict,
            reasonCodes: normalizedReasonCodes,
            approvals: normalizedApprovals,
            policyID: policyID,
            policyVersion: policyVersion,
            decidedAt: decidedAt,
            decisionDigest: digest
        )
    }
}

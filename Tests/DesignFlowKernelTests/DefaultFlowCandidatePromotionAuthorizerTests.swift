import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation
import Testing
@testable import DesignFlowKernel

@Suite("Default candidate promotion authorizer")
struct DefaultFlowCandidatePromotionAuthorizerTests {
    @Test("exact persisted human approval authorizes the candidate")
    func authorizesExactPersistedEvidence() async throws {
        let fixture = try PromotionFixture()
        let authorizer = fixture.authorizer()

        let decision = try await authorizer.decidePromotion(fixture.request)
        #expect(decision.verdict == .authorized)
        #expect(decision.approvals == [fixture.approvalArtifact.reference])
        #expect(decision.designDiff == fixture.request.designDiffArtifact.reference)

        let authorization = try await authorizer.issuePromotionAuthorization(
            for: decision,
            request: fixture.request
        )
        #expect(authorization.desiredRevision == fixture.evidence.candidateRevision)
        #expect(authorization.expectedRevision == fixture.evidence.baseRevision)
        #expect(authorization.evidenceBindingDigest == fixture.evidence.bindingDigest)
        try FlowCandidatePromotionAuthorizationValidator().validate(
            authorization,
            decision: decision,
            request: fixture.request,
            at: fixture.decisionDate
        )
    }

    @Test("approval for another evidence artifact is rejected")
    func rejectsApprovalForAnotherEvidenceArtifact() async throws {
        let fixture = try PromotionFixture(bindApprovalToAnotherEvidence: true)

        do {
            _ = try await fixture.authorizer().decidePromotion(fixture.request)
            Issue.record("An approval bound to another evidence artifact must be rejected.")
        } catch let error as DefaultFlowCandidatePromotionAuthorizerError {
            #expect(
                error == .approvalEvidenceMismatch(
                    logicalID: fixture.approvalArtifact.logicalID
                )
            )
        }
    }

    @Test("approval for another design diff is rejected")
    func rejectsApprovalForAnotherDesignDiff() async throws {
        let fixture = try PromotionFixture(bindApprovalToAnotherDiff: true)

        do {
            _ = try await fixture.authorizer().decidePromotion(fixture.request)
            Issue.record("An approval bound to another design diff must be rejected.")
        } catch let error as DefaultFlowCandidatePromotionAuthorizerError {
            #expect(
                error == .approvalEvidenceMismatch(
                    logicalID: fixture.approvalArtifact.logicalID
                )
            )
        }
    }

    @Test("authorization rejects a request that substitutes another design diff")
    func rejectsSubstitutedDesignDiffRequest() async throws {
        let fixture = try PromotionFixture()
        let authorizer = fixture.authorizer()
        let decision = try await authorizer.decidePromotion(fixture.request)
        let authorization = try await authorizer.issuePromotionAuthorization(
            for: decision,
            request: fixture.request
        )
        let alteredRequest = FlowCandidatePromotionRequest(
            evidenceBinding: fixture.request.evidenceBinding,
            evidenceBindingArtifact: fixture.request.evidenceBindingArtifact,
            designDiffArtifact: fixture.alternateDesignDiffArtifact,
            approvalArtifacts: fixture.request.approvalArtifacts,
            targetReferenceName: fixture.request.targetReferenceName,
            expectedGeneration: fixture.request.expectedGeneration,
            expectedRevision: fixture.request.expectedRevision
        )

        do {
            try FlowCandidatePromotionAuthorizationValidator().validate(
                authorization,
                decision: decision,
                request: alteredRequest,
                at: fixture.decisionDate
            )
            Issue.record("A substituted design diff must invalidate authorization.")
        } catch let error as FlowCandidatePromotionAuthorizationValidationError {
            #expect(error == .designDiffArtifactMismatch)
        }
    }

    @Test("decision and authorization digests are recomputed")
    func rejectsAlteredPolicyDigests() async throws {
        let fixture = try PromotionFixture()
        let authorizer = fixture.authorizer()
        let decision = try await authorizer.decidePromotion(fixture.request)
        let authorization = try await authorizer.issuePromotionAuthorization(
            for: decision,
            request: fixture.request
        )

        let alteredDecision = FlowCandidatePromotionDecision(
            decisionID: decision.decisionID,
            runID: decision.runID,
            candidateRevision: decision.candidateRevision,
            semanticGraphDigest: decision.semanticGraphDigest,
            evidenceBindingDigest: decision.evidenceBindingDigest,
            designDiff: decision.designDiff,
            verdict: decision.verdict,
            reasonCodes: decision.reasonCodes,
            approvals: decision.approvals,
            policyID: decision.policyID,
            policyVersion: decision.policyVersion,
            decidedAt: decision.decidedAt,
            decisionDigest: fixture.otherDigest
        )
        do {
            try FlowCandidatePromotionDecisionValidator().validate(alteredDecision)
            Issue.record("An altered decision digest must be rejected.")
        } catch let error as FlowCandidatePromotionDecisionValidationError {
            guard case .decisionDigestMismatch = error else {
                Issue.record("Expected a decision digest mismatch, received \(error).")
                return
            }
        }

        let alteredAuthorization = FlowCandidatePromotionAuthorization(
            authorizationID: authorization.authorizationID,
            decisionID: authorization.decisionID,
            decisionDigest: authorization.decisionDigest,
            databaseID: authorization.databaseID,
            targetReferenceName: authorization.targetReferenceName,
            expectedGeneration: authorization.expectedGeneration,
            expectedRevision: authorization.expectedRevision,
            desiredRevision: authorization.desiredRevision,
            semanticGraphDigest: authorization.semanticGraphDigest,
            evidenceBindingDigest: authorization.evidenceBindingDigest,
            issuedAt: authorization.issuedAt,
            expiresAt: authorization.expiresAt,
            authorizationDigest: fixture.otherDigest
        )
        do {
            try FlowCandidatePromotionAuthorizationValidator().validate(
                alteredAuthorization,
                decision: decision,
                request: fixture.request,
                at: fixture.decisionDate
            )
            Issue.record("An altered authorization digest must be rejected.")
        } catch let error as FlowCandidatePromotionAuthorizationValidationError {
            guard case .authorizationDigestMismatch = error else {
                Issue.record("Expected an authorization digest mismatch, received \(error).")
                return
            }
        }
    }
}

private struct PromotionFixture {
    let decisionDate = Date(timeIntervalSince1970: 1_786_291_200)
    let evidence: FlowCandidateEvidenceBinding
    let evidenceArtifact: FlowArtifactBinding
    let approvalArtifact: FlowArtifactBinding
    let alternateDesignDiffArtifact: FlowArtifactBinding
    let request: FlowCandidatePromotionRequest
    let reader: PromotionArtifactReader
    let policy: FlowCandidatePromotionPolicy
    let otherDigest: ContentDigest

    init(
        bindApprovalToAnotherEvidence: Bool = false,
        bindApprovalToAnotherDiff: Bool = false
    ) throws {
        let databaseID = try DesignDatabaseID(high: 41, low: 1)
        let baseRevision = DesignRevisionReference(
            databaseID: databaseID,
            revisionID: DesignRevisionID(high: 41, low: 2)
        )
        let candidateRevision = DesignRevisionReference(
            databaseID: databaseID,
            revisionID: DesignRevisionID(high: 41, low: 3)
        )
        let graphDigest = try Self.digest(character: "1")
        otherDigest = try Self.digest(character: "2")

        let commitContent = Data("candidate commit receipt".utf8)
        let commitArtifact = try Self.binding(
            content: commitContent,
            logicalID: "candidate-commit-receipt",
            path: "candidate-commit.json"
        )
        let stageResultContent = Data("drc stage result".utf8)
        let stageResultArtifact = try Self.binding(
            content: stageResultContent,
            logicalID: "drc-stage-result",
            path: "drc-result.json"
        )
        let stageEvidence = FlowCandidateStageEvidence(
            stageID: "drc.native",
            candidateRevision: candidateRevision,
            semanticGraphDigest: graphDigest,
            result: stageResultArtifact.reference,
            rawEvidence: [],
            status: .succeeded
        )
        evidence = try FlowCandidateEvidenceBinding.contentAddressed(
            runID: "promotion-run",
            baseRevision: baseRevision,
            candidateRevision: candidateRevision,
            semanticGraphDigest: graphDigest,
            resolutionEvidenceDigest: otherDigest,
            mutationPlanDigest: otherDigest,
            commitReceipt: commitArtifact.reference,
            stageEvidence: [stageEvidence]
        )
        let evidenceContent = try JSONEncoder().encode(evidence)
        evidenceArtifact = try Self.binding(
            content: evidenceContent,
            logicalID: "candidate-evidence-binding",
            path: "candidate-evidence.json"
        )
        let designDiffContent = Data(#"{"stateChanged":true}"#.utf8)
        let designDiffArtifact = try Self.binding(
            content: designDiffContent,
            logicalID: "candidate-design-revision-diff",
            path: "candidate-design-revision-diff.json",
            kind: .designDiff
        )
        alternateDesignDiffArtifact = try Self.binding(
            content: Data(#"{"stateChanged":false}"#.utf8),
            logicalID: "another-candidate-design-revision-diff",
            path: "another-candidate-design-revision-diff.json",
            kind: .designDiff
        )
        let reviewedEvidence: FlowArtifactBinding
        if bindApprovalToAnotherEvidence {
            reviewedEvidence = try Self.binding(
                content: Data("another candidate evidence".utf8),
                logicalID: "another-candidate-evidence",
                path: "another-candidate-evidence.json"
            )
        } else {
            reviewedEvidence = evidenceArtifact
        }
        let reviewedDesignDiff: FlowArtifactBinding
        if bindApprovalToAnotherDiff {
            reviewedDesignDiff = alternateDesignDiffArtifact
        } else {
            reviewedDesignDiff = designDiffArtifact
        }
        let approval = FlowApprovalRecord(
            runID: evidence.runID,
            stageID: "promotion-review",
            verdict: .approved,
            reviewer: "human-reviewer",
            reviewerKind: .human,
            createdAt: decisionDate.addingTimeInterval(-30),
            evidence: FlowApprovalEvidenceBinding(
                plan: commitArtifact,
                stageResult: reviewedEvidence,
                designDiff: reviewedDesignDiff
            )
        )
        let approvalContent = try JSONEncoder().encode(approval)
        approvalArtifact = try Self.binding(
            content: approvalContent,
            logicalID: "promotion-approval",
            path: "promotion-approval.json"
        )
        request = FlowCandidatePromotionRequest(
            evidenceBinding: evidence,
            evidenceBindingArtifact: evidenceArtifact,
            designDiffArtifact: designDiffArtifact,
            approvalArtifacts: [approvalArtifact],
            targetReferenceName: "main",
            expectedGeneration: 7,
            expectedRevision: baseRevision
        )
        reader = PromotionArtifactReader(contentByAvailability: [
            evidenceArtifact.availability: evidenceContent,
            designDiffArtifact.availability: designDiffContent,
            approvalArtifact.availability: approvalContent,
        ])
        policy = try FlowCandidatePromotionPolicy(
            policyID: "production-promotion",
            policyVersion: "1",
            requiredStageIDs: ["drc.native"],
            approvalStageID: "promotion-review"
        )
    }

    func authorizer() -> DefaultFlowCandidatePromotionAuthorizer {
        DefaultFlowCandidatePromotionAuthorizer(
            reader: reader,
            policy: policy,
            currentDate: { decisionDate }
        )
    }

    private static func digest(character: Character) throws -> ContentDigest {
        try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: character, count: 64)
        )
    }

    private static func binding(
        content: Data,
        logicalID: String,
        path: String,
        kind: ArtifactKind = .report
    ) throws -> FlowArtifactBinding {
        let reference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: content),
            byteCount: UInt64(content.count),
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: kind,
                format: .json
            )
        )
        return try FlowArtifactBinding(
            logicalID: logicalID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(rawValue: "promotion-test"),
                relativePath: ArtifactRelativePath(segments: [path])
            )
        )
    }
}

private struct PromotionArtifactReader: FlowCandidatePromotionArtifactReading {
    let contentByAvailability: [ArtifactAvailability: Data]

    func loadArtifactContent(
        for artifact: FlowArtifactBinding
    ) async throws -> Data {
        guard let content = contentByAvailability[artifact.availability] else {
            throw PromotionArtifactReaderError.missingArtifact(artifact.logicalID)
        }
        return content
    }
}

private enum PromotionArtifactReaderError: Error {
    case missingArtifact(String)
}

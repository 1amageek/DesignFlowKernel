import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public struct DefaultFlowCandidatePromotionAuthorizer:
    FlowCandidatePromotionAuthorizing {
    private let reader: any FlowCandidatePromotionArtifactReading
    private let policy: FlowCandidatePromotionPolicy
    private let digester: any ContentDigesting
    private let currentDate: @Sendable () -> Date

    public init(
        reader: any FlowCandidatePromotionArtifactReading,
        policy: FlowCandidatePromotionPolicy,
        digester: any ContentDigesting = SHA256ContentDigester(),
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.reader = reader
        self.policy = policy
        self.digester = digester
        self.currentDate = currentDate
    }

    public func decidePromotion(
        _ request: FlowCandidatePromotionRequest
    ) async throws -> FlowCandidatePromotionDecision {
        try await makeDecision(request, decidedAt: currentDate())
    }

    public func issuePromotionAuthorization(
        for decision: FlowCandidatePromotionDecision,
        request: FlowCandidatePromotionRequest
    ) async throws -> FlowCandidatePromotionAuthorization {
        let expectedDecision = try await makeDecision(
            request,
            decidedAt: decision.decidedAt
        )
        guard expectedDecision == decision else {
            throw DefaultFlowCandidatePromotionAuthorizerError.decisionMismatch
        }
        guard decision.verdict == .authorized else {
            throw DefaultFlowCandidatePromotionAuthorizerError.decisionNotAuthorized
        }
        let issuedAt = currentDate()
        guard issuedAt >= decision.decidedAt else {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .authorizationClockPrecedesDecision
        }
        let authorizationID = [
            decision.decisionID,
            request.targetReferenceName,
            String(request.expectedGeneration),
        ].joined(separator: "-")
        let authorization: FlowCandidatePromotionAuthorization
        do {
            authorization = try FlowCandidatePromotionAuthorization.contentAddressed(
                authorizationID: authorizationID,
                decisionID: decision.decisionID,
                decisionDigest: decision.decisionDigest,
                databaseID: decision.candidateRevision.databaseID,
                targetReferenceName: request.targetReferenceName,
                expectedGeneration: request.expectedGeneration,
                expectedRevision: request.expectedRevision,
                desiredRevision: decision.candidateRevision,
                semanticGraphDigest: decision.semanticGraphDigest,
                evidenceBindingDigest: decision.evidenceBindingDigest,
                issuedAt: issuedAt,
                expiresAt: issuedAt.addingTimeInterval(
                    policy.authorizationValiditySeconds
                ),
                using: digester
            )
            try FlowCandidatePromotionAuthorizationValidator().validate(
                authorization,
                decision: decision,
                request: request,
                at: issuedAt
            )
        } catch {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .authorizationBuildFailed(String(describing: error))
        }
        return authorization
    }

    private func makeDecision(
        _ request: FlowCandidatePromotionRequest,
        decidedAt: Date
    ) async throws -> FlowCandidatePromotionDecision {
        guard !request.targetReferenceName.isEmpty else {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .emptyTargetReferenceName
        }
        do {
            try FlowCandidateEvidenceBindingValidator().validate(
                request.evidenceBinding,
                requiredStageIDs: policy.requiredStageIDs
            )
        } catch {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .evidenceInvalid(String(describing: error))
        }
        if let unsuccessful = request.evidenceBinding.stageEvidence.first(where: {
            $0.status != .succeeded
        }) {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .unsuccessfulRetainedStage(unsuccessful.stageID)
        }
        let persistedEvidence: FlowCandidateEvidenceBinding = try await load(
            request.evidenceBindingArtifact,
            as: FlowCandidateEvidenceBinding.self
        )
        guard persistedEvidence == request.evidenceBinding else {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .evidenceArtifactMismatch
        }
        guard request.designDiffArtifact.role == .output,
              request.designDiffArtifact.kind == .designDiff,
              request.designDiffArtifact.format == .json else {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .designDiffArtifactInvalid(
                    logicalID: request.designDiffArtifact.logicalID
                )
        }
        _ = try await content(for: request.designDiffArtifact)

        var approvalIDs = Set<ArtifactID>()
        var approvals: [(binding: FlowArtifactBinding, record: FlowApprovalRecord)] = []
        approvals.reserveCapacity(request.approvalArtifacts.count)
        for binding in request.approvalArtifacts {
            guard approvalIDs.insert(binding.reference.id).inserted else {
                throw DefaultFlowCandidatePromotionAuthorizerError
                    .duplicateApprovalArtifact(binding.reference.id)
            }
            let record: FlowApprovalRecord = try await load(
                binding,
                as: FlowApprovalRecord.self
            )
            try validateApproval(
                record,
                binding: binding,
                request: request,
                decidedAt: decidedAt
            )
            approvals.append((binding, record))
        }

        let verdict: FlowCandidatePromotionDecision.Verdict
        let reasonCodes: [String]
        if approvals.contains(where: { $0.record.verdict == .rejected }) {
            verdict = .rejected
            reasonCodes = ["approval-rejected"]
        } else {
            let acceptedCount = approvals.reduce(into: UInt32(0)) { count, approval in
                switch approval.record.verdict {
                case .approved:
                    count += 1
                case .waived where policy.allowWaivers:
                    count += 1
                case .waived, .rejected:
                    break
                }
            }
            if acceptedCount >= policy.requiredApprovalCount {
                verdict = .authorized
                reasonCodes = ["policy-requirements-satisfied"]
            } else {
                verdict = .needsEvidence
                reasonCodes = ["approval-count-insufficient"]
            }
        }

        do {
            let decision = try FlowCandidatePromotionDecision.contentAddressed(
                decisionID: [
                    policy.policyID,
                    request.evidenceBinding.runID,
                    "promotion",
                ].joined(separator: "-"),
                runID: request.evidenceBinding.runID,
                candidateRevision: request.evidenceBinding.candidateRevision,
                semanticGraphDigest: request.evidenceBinding.semanticGraphDigest,
                evidenceBindingDigest: request.evidenceBinding.bindingDigest,
                designDiff: request.designDiffArtifact.reference,
                verdict: verdict,
                reasonCodes: reasonCodes,
                approvals: approvals.map(\.binding.reference),
                policyID: policy.policyID,
                policyVersion: policy.policyVersion,
                decidedAt: decidedAt,
                using: digester
            )
            try FlowCandidatePromotionDecisionValidator().validate(decision)
            return decision
        } catch {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .decisionBuildFailed(String(describing: error))
        }
    }

    private func validateApproval(
        _ approval: FlowApprovalRecord,
        binding: FlowArtifactBinding,
        request: FlowCandidatePromotionRequest,
        decidedAt: Date
    ) throws {
        guard approval.runID == request.evidenceBinding.runID else {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .approvalRunIDMismatch(logicalID: binding.logicalID)
        }
        guard approval.stageID == policy.approvalStageID else {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .approvalStageIDMismatch(logicalID: binding.logicalID)
        }
        guard approval.evidence.stageResult == request.evidenceBindingArtifact,
              approval.evidence.designDiff == request.designDiffArtifact,
              approval.evidence.plan.reference
                == request.evidenceBinding.commitReceipt else {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .approvalEvidenceMismatch(logicalID: binding.logicalID)
        }
        if policy.requireHumanReviewer, approval.reviewerKind != .human {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .approvalReviewerRequired(logicalID: binding.logicalID)
        }
        guard approval.createdAt <= decidedAt else {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .approvalFromFuture(logicalID: binding.logicalID)
        }
    }

    private func load<Value: Decodable>(
        _ binding: FlowArtifactBinding,
        as type: Value.Type
    ) async throws -> Value {
        let data = try await content(for: binding)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .artifactDecodeFailed(
                    logicalID: binding.logicalID,
                    reason: String(describing: error)
                )
        }
    }

    private func content(
        for binding: FlowArtifactBinding
    ) async throws -> Data {
        let reference = binding.reference
        guard reference.byteCount <= policy.maximumArtifactByteCount else {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .artifactBudgetExceeded(
                    logicalID: binding.logicalID,
                    actual: reference.byteCount,
                    maximum: policy.maximumArtifactByteCount
                )
        }
        let data: Data
        do {
            data = try await reader.loadArtifactContent(for: binding)
        } catch {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .artifactReadFailed(
                    logicalID: binding.logicalID,
                    reason: String(describing: error)
                )
        }
        guard UInt64(data.count) == reference.byteCount else {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .artifactSizeMismatch(
                    logicalID: binding.logicalID,
                    expected: reference.byteCount,
                    actual: UInt64(data.count)
                )
        }
        let actualDigest: ContentDigest
        do {
            actualDigest = try digester.digest(data: data)
        } catch {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .artifactDigestComputationFailed(
                    logicalID: binding.logicalID,
                    reason: String(describing: error)
                )
        }
        guard actualDigest == reference.digest else {
            throw DefaultFlowCandidatePromotionAuthorizerError
                .artifactDigestMismatch(logicalID: binding.logicalID)
        }
        return data
    }
}

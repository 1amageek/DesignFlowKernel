import CircuiteFoundation

public struct FlowCandidateEvidenceBindingValidator: Sendable {
    public init() {}

    public func validate(
        _ binding: FlowCandidateEvidenceBinding,
        requiredStageIDs: Set<String>
    ) throws {
        let expectedBindingDigest: ContentDigest
        do {
            expectedBindingDigest = try FlowCandidateEvidenceBindingDigest.make(
                runID: binding.runID,
                baseRevision: binding.baseRevision,
                candidateRevision: binding.candidateRevision,
                semanticGraphDigest: binding.semanticGraphDigest,
                resolutionEvidenceDigest: binding.resolutionEvidenceDigest,
                mutationPlanDigest: binding.mutationPlanDigest,
                commitReceipt: binding.commitReceipt,
                stageEvidence: binding.stageEvidence
            )
        } catch {
            throw FlowCandidateEvidenceBindingValidationError
                .bindingDigestComputationFailed(String(describing: error))
        }
        guard expectedBindingDigest == binding.bindingDigest else {
            throw FlowCandidateEvidenceBindingValidationError.bindingDigestMismatch(
                expected: expectedBindingDigest,
                actual: binding.bindingDigest
            )
        }
        guard binding.baseRevision.databaseID == binding.candidateRevision.databaseID else {
            throw FlowCandidateEvidenceBindingValidationError.crossDatabaseBaseRevision(
                base: binding.baseRevision.databaseID,
                candidate: binding.candidateRevision.databaseID
            )
        }

        var stagesByID: [String: FlowCandidateStageEvidence] = [:]
        for evidence in binding.stageEvidence {
            guard stagesByID.updateValue(evidence, forKey: evidence.stageID) == nil else {
                throw FlowCandidateEvidenceBindingValidationError.duplicateStageID(
                    evidence.stageID
                )
            }
            guard evidence.candidateRevision == binding.candidateRevision else {
                throw FlowCandidateEvidenceBindingValidationError.candidateRevisionMismatch(
                    stageID: evidence.stageID,
                    expected: binding.candidateRevision,
                    actual: evidence.candidateRevision
                )
            }
            guard evidence.semanticGraphDigest == binding.semanticGraphDigest else {
                throw FlowCandidateEvidenceBindingValidationError.semanticGraphDigestMismatch(
                    stageID: evidence.stageID,
                    expected: binding.semanticGraphDigest,
                    actual: evidence.semanticGraphDigest
                )
            }
        }

        for stageID in requiredStageIDs {
            guard let evidence = stagesByID[stageID] else {
                throw FlowCandidateEvidenceBindingValidationError.missingRequiredStage(stageID)
            }
            guard evidence.status == .succeeded else {
                throw FlowCandidateEvidenceBindingValidationError.requiredStageDidNotSucceed(
                    stageID: stageID,
                    status: evidence.status
                )
            }
        }
    }
}

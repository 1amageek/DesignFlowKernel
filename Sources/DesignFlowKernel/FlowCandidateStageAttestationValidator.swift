import CircuiteFoundation

public struct FlowCandidateStageAttestationValidator: Sendable {
    public init() {}

    public func validate(
        _ attestation: FlowCandidateStageAttestation
    ) throws {
        guard attestation.schemaVersion
            == FlowCandidateStageAttestation.currentSchemaVersion else {
            throw FlowCandidateStageAttestationValidationError
                .unsupportedSchemaVersion(attestation.schemaVersion)
        }
        for (field, value) in [
            ("runID", attestation.runID),
            ("stageID", attestation.stageID),
            ("evidenceType", attestation.evidenceType),
        ] where value.isEmpty {
            throw FlowCandidateStageAttestationValidationError.emptyField(field)
        }

        var rawEvidenceIDs = Set<ArtifactID>()
        for reference in attestation.rawEvidence
            where !rawEvidenceIDs.insert(reference.id).inserted {
            throw FlowCandidateStageAttestationValidationError
                .duplicateRawEvidence(reference.id)
        }
        guard !rawEvidenceIDs.contains(attestation.result.id) else {
            throw FlowCandidateStageAttestationValidationError
                .resultRepeatedAsRawEvidence(attestation.result.id)
        }
        var inputArtifactIDs = Set<ArtifactID>()
        for reference in attestation.inputArtifacts
            where !inputArtifactIDs.insert(reference.id).inserted {
            throw FlowCandidateStageAttestationValidationError
                .duplicateInputArtifact(reference.id)
        }
        let outputIDs = rawEvidenceIDs.union([attestation.result.id])
        if let overlap = inputArtifactIDs.intersection(outputIDs).first {
            throw FlowCandidateStageAttestationValidationError
                .inputOutputOverlap(overlap)
        }

        let expectedDigest: ContentDigest
        do {
            expectedDigest = try FlowCandidateStageAttestationDigest.make(
                runID: attestation.runID,
                stageID: attestation.stageID,
                evidenceType: attestation.evidenceType,
                candidateRevision: attestation.candidateRevision,
                semanticGraphDigest: attestation.semanticGraphDigest,
                commitReceipt: attestation.commitReceipt,
                result: attestation.result,
                rawEvidence: attestation.rawEvidence,
                inputArtifacts: attestation.inputArtifacts,
                status: attestation.status
            )
        } catch {
            throw FlowCandidateStageAttestationValidationError
                .attestationDigestComputationFailed(String(describing: error))
        }
        guard expectedDigest == attestation.attestationDigest else {
            throw FlowCandidateStageAttestationValidationError
                .attestationDigestMismatch(
                    expected: expectedDigest,
                    actual: attestation.attestationDigest
                )
        }
    }
}

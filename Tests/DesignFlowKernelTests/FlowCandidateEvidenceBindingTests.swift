import CircuiteFoundation
import Testing
@testable import DesignFlowKernel

@Suite("Candidate evidence binding")
struct FlowCandidateEvidenceBindingTests {
    @Test("exact candidate revision and semantic graph are required")
    func validatesExactLineage() throws {
        let fixture = try Fixture()
        try FlowCandidateEvidenceBindingValidator().validate(
            fixture.binding,
            requiredStageIDs: ["drc.native"]
        )

        let wrongRevision = FlowCandidateStageEvidence(
            stageID: "drc.native",
            candidateRevision: fixture.baseRevision,
            semanticGraphDigest: fixture.graphDigest,
            result: fixture.artifact,
            rawEvidence: [],
            status: .succeeded
        )
        do {
            try FlowCandidateEvidenceBindingValidator().validate(
                fixture.binding(stageEvidence: [wrongRevision]),
                requiredStageIDs: ["drc.native"]
            )
            Issue.record("Evidence from a different revision must be rejected.")
        } catch let error as FlowCandidateEvidenceBindingValidationError {
            #expect(
                error == .candidateRevisionMismatch(
                    stageID: "drc.native",
                    expected: fixture.candidateRevision,
                    actual: fixture.baseRevision
                )
            )
        }

        let wrongGraph = FlowCandidateStageEvidence(
            stageID: "drc.native",
            candidateRevision: fixture.candidateRevision,
            semanticGraphDigest: fixture.otherDigest,
            result: fixture.artifact,
            rawEvidence: [],
            status: .succeeded
        )
        do {
            try FlowCandidateEvidenceBindingValidator().validate(
                fixture.binding(stageEvidence: [wrongGraph]),
                requiredStageIDs: ["drc.native"]
            )
            Issue.record("Evidence from a different semantic graph must be rejected.")
        } catch let error as FlowCandidateEvidenceBindingValidationError {
            #expect(
                error == .semanticGraphDigestMismatch(
                    stageID: "drc.native",
                    expected: fixture.graphDigest,
                    actual: fixture.otherDigest
                )
            )
        }
    }

    @Test("required stage must exist and succeed")
    func requiredStageMustSucceed() throws {
        let fixture = try Fixture()
        do {
            try FlowCandidateEvidenceBindingValidator().validate(
                fixture.binding,
                requiredStageIDs: ["lvs.native"]
            )
            Issue.record("Missing required evidence must be rejected.")
        } catch let error as FlowCandidateEvidenceBindingValidationError {
            #expect(error == .missingRequiredStage("lvs.native"))
        }

        let failed = FlowCandidateStageEvidence(
            stageID: "drc.native",
            candidateRevision: fixture.candidateRevision,
            semanticGraphDigest: fixture.graphDigest,
            result: fixture.artifact,
            rawEvidence: [],
            status: .failed
        )
        do {
            try FlowCandidateEvidenceBindingValidator().validate(
                fixture.binding(stageEvidence: [failed]),
                requiredStageIDs: ["drc.native"]
            )
            Issue.record("Failed required evidence must be rejected.")
        } catch let error as FlowCandidateEvidenceBindingValidationError {
            #expect(
                error == .requiredStageDidNotSucceed(
                    stageID: "drc.native",
                    status: .failed
                )
            )
        }
    }

    @Test("binding digest is recomputed from canonical evidence")
    func rejectsAlteredBindingDigest() throws {
        let fixture = try Fixture()
        let altered = FlowCandidateEvidenceBinding(
            runID: fixture.binding.runID,
            baseRevision: fixture.binding.baseRevision,
            candidateRevision: fixture.binding.candidateRevision,
            semanticGraphDigest: fixture.binding.semanticGraphDigest,
            resolutionEvidenceDigest: fixture.binding.resolutionEvidenceDigest,
            mutationPlanDigest: fixture.binding.mutationPlanDigest,
            commitReceipt: fixture.binding.commitReceipt,
            stageEvidence: fixture.binding.stageEvidence,
            bindingDigest: fixture.otherDigest
        )

        do {
            try FlowCandidateEvidenceBindingValidator().validate(
                altered,
                requiredStageIDs: ["drc.native"]
            )
            Issue.record("An altered binding digest must be rejected.")
        } catch let error as FlowCandidateEvidenceBindingValidationError {
            guard case let .bindingDigestMismatch(expected, actual) = error else {
                Issue.record("Expected a binding digest mismatch, received \(error).")
                return
            }
            #expect(expected == fixture.binding.bindingDigest)
            #expect(actual == fixture.otherDigest)
        }
    }
}

private struct Fixture {
    let baseRevision: DesignRevisionReference
    let candidateRevision: DesignRevisionReference
    let graphDigest: ContentDigest
    let otherDigest: ContentDigest
    let artifact: ArtifactReference
    let binding: FlowCandidateEvidenceBinding

    init() throws {
        let databaseID = try DesignDatabaseID(high: 1, low: 1)
        baseRevision = DesignRevisionReference(
            databaseID: databaseID,
            revisionID: DesignRevisionID(high: 1, low: 2)
        )
        candidateRevision = DesignRevisionReference(
            databaseID: databaseID,
            revisionID: DesignRevisionID(high: 1, low: 3)
        )
        graphDigest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "1", count: 64)
        )
        otherDigest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "2", count: 64)
        )
        artifact = try ArtifactReference(
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "3", count: 64)
            ),
            byteCount: 10,
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: .report,
                format: .json
            )
        )
        let stage = FlowCandidateStageEvidence(
            stageID: "drc.native",
            candidateRevision: candidateRevision,
            semanticGraphDigest: graphDigest,
            result: artifact,
            rawEvidence: [],
            status: .succeeded
        )
        binding = try FlowCandidateEvidenceBinding.contentAddressed(
            runID: "candidate-binding",
            baseRevision: baseRevision,
            candidateRevision: candidateRevision,
            semanticGraphDigest: graphDigest,
            resolutionEvidenceDigest: otherDigest,
            mutationPlanDigest: otherDigest,
            commitReceipt: artifact,
            stageEvidence: [stage]
        )
    }

    func binding(
        stageEvidence: [FlowCandidateStageEvidence]
    ) throws -> FlowCandidateEvidenceBinding {
        try FlowCandidateEvidenceBinding.contentAddressed(
            runID: binding.runID,
            baseRevision: binding.baseRevision,
            candidateRevision: binding.candidateRevision,
            semanticGraphDigest: binding.semanticGraphDigest,
            resolutionEvidenceDigest: binding.resolutionEvidenceDigest,
            mutationPlanDigest: binding.mutationPlanDigest,
            commitReceipt: binding.commitReceipt,
            stageEvidence: stageEvidence
        )
    }
}

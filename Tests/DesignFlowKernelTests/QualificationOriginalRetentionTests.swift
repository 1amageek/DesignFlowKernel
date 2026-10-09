import Foundation
import Testing
import ToolQualification
@testable import DesignFlowKernel

@Suite("Qualification original retention", .timeLimit(.minutes(1)))
struct QualificationOriginalRetentionTests {
    @Test func modelFreeCaseRetainsCompletedPhase() async throws {
        let root = try FlowRunLedgerSummaryTests().makeTemporaryRoot("qualification-original")
        defer { FlowRunLedgerSummaryTests().removeTemporaryRoot(root) }
        let record = try await TestToolQualificationFixtures.qualificationRecord(for: FlowRunLedgerSummaryTests().drcDescriptor(), projectRoot: root)
        let reader = await TestFlowInfrastructure.bound(to: root)
        let corpusEvidence = try #require(record.health.evidence.first { $0.kind == .corpus }?.artifact)
        let corpus = try ToolCorpusQualificationResult.decodeCanonical(from: await reader.verifiedData(for: corpusEvidence))
        let original = try #require(corpus.cases.first?.originalExecutionArtifact)
        let execution = try ToolQualificationCaseExecution.decodeCanonical(from: await reader.verifiedData(for: original))
        #expect(corpus.outputArtifacts.contains(original))
        #expect(execution.producer.identifier == record.descriptor.toolID)
        #expect(execution.producer.version == corpus.scope.toolVersion)
        #expect(execution.phaseIDs == ["fixture"])
        #expect(execution.metricPhaseIDs == ["pass": ["fixture"]])
        #expect(execution.modelReceiptArtifacts.isEmpty)
        #expect(record.descriptor.trustProfile.processQualification == nil)
        _ = try await ToolQualificationRecordValidator().validatedRecord(record,
            expectedToolID: record.descriptor.toolID, reading: reader)
    }

    @Test(arguments: ["missing", "altered"])
    func missingOrAlteredOriginalRefusesRecord(_ failure: String) async throws {
        let root = try FlowRunLedgerSummaryTests().makeTemporaryRoot("qualification-original-refusal")
        defer { FlowRunLedgerSummaryTests().removeTemporaryRoot(root) }
        let record = try await TestToolQualificationFixtures.qualificationRecord(for: FlowRunLedgerSummaryTests().drcDescriptor(), projectRoot: root)
        let url = root.appending(path: ".xcircuite/qualification/test-fixtures/native-drc-primary-original.json")
        if failure == "missing" {
            try FileManager.default.removeItem(at: url)
        } else {
            var bytes = try Data(contentsOf: url)
            bytes[0] ^= 1
            try bytes.write(to: url, options: .atomic)
        }
        let reader = await TestFlowInfrastructure.bound(to: root)
        let requirement = ToolTrustRequirement(kind: .drc, operationID: "run-drc",
            minimumLevel: .smokeChecked, requiredQualifiedEvidenceKinds: [.corpus])
        let decision = await ToolTrustEvaluator().evaluate(descriptor: record.descriptor,
            requirement: requirement, health: record.health, artifactReader: reader,
            evaluatedAt: record.issuedAt)
        #expect(decision.status == .rejected)
        #expect(decision.diagnostics.contains { $0.code == "QUALIFICATION_BOUND_ARTIFACT_INTEGRITY_FAILED" })
    }
}

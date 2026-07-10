import DesignFlowKernel
import DesignFlowCLISupport
import Foundation
import Testing
import ToolQualification
import XcircuitePackage

extension FlowRunLedgerSummaryTests {
@Test func reviewRunCLICommandEmitsArtifactCoverageRepairItemJSON() async throws {
    let root = try makeTemporaryRoot("agent-review-artifact-coverage-cli")
    defer { removeTemporaryRoot(root) }
    try await createArtifactCoverageFailureRun(root: root, runID: "run-1")

    let json = try DesignFlowCLICommand.run(
        arguments: [
            "review-run",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let bundle = try JSONDecoder().decode(FlowRunReviewBundle.self, from: data)

    #expect(bundle.reviewItems.contains {
        $0.kind == .artifactCoverage
            && $0.nextActionID == "001-drc-repair-drc-artifacts"
    })
}

@Test func reviewRunCLICommandEmitsPlanningCorrectnessItemJSON() async throws {
    let root = try makeTemporaryRoot("agent-review-planning-correctness-cli")
    defer { removeTemporaryRoot(root) }
    let planVerificationPath = ".xcircuite/runs/run-1/planning/plan-verification.json"
    let payload = Data("""
    {"schemaVersion":1,"planID":"plan-1","accepted":false,"correctnessGateResults":[{"gateID":"problem-validation","status":"passed","summary":"Planning problem was validated.","diagnostics":[],"nextActions":[]},{"gateID":"planner-replay","status":"blocked","summary":"Planner replay did not satisfy all goal atoms.","diagnostics":[{"code":"missing-goal-atoms"}],"nextActions":["repair-planning-problem-goals"]}]}
    """.utf8)

    try await createBlockedApprovalRun(root: root, runID: "run-1")
    try FileManager.default.createDirectory(
        at: root.appending(path: planVerificationPath).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try payload.write(to: root.appending(path: planVerificationPath), options: .atomic)
    let reference = try XcircuitePackageStore().fileReference(
        forProjectRelativePath: planVerificationPath,
        artifactID: "planning-plan-verification",
        kind: .other,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try XcircuitePackageStore().upsertRunArtifact(reference, runID: "run-1", inProjectAt: root)

    let json = try DesignFlowCLICommand.run(
        arguments: [
            "review-run",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let bundle = try JSONDecoder().decode(FlowRunReviewBundle.self, from: data)

    let planningCorrectnessItem = try #require(bundle.reviewItems.first {
        $0.kind == .planningCorrectness
            && $0.itemID == "planning-correctness-planner-replay"
    })
    #expect(planningCorrectnessItem.status == .needsRepair)
    #expect(planningCorrectnessItem.severity == .warning)
    #expect(planningCorrectnessItem.diagnosticCodes == ["missing-goal-atoms"])
    #expect(planningCorrectnessItem.artifactPaths == [planVerificationPath])
    #expect(planningCorrectnessItem.nextActionID == "repair-planning-problem-goals")
}

@Test func reviewRunCLICommandEmitsProblemTranslationAuditItemJSON() async throws {
    let root = try makeTemporaryRoot("agent-review-problem-translation-audit-cli")
    defer { removeTemporaryRoot(root) }
    let auditPath = ".xcircuite/runs/run-1/planning/problem-translation-audit.json"
    let payload = Data("""
    {"schemaVersion":1,"status":"failed","problemID":"problem-1","blocking":true,"diagnostics":[{"severity":"error","code":"orphan-candidate-action","message":"Candidate action action-1 has no valid source objective.","nextActions":["attach-action-source-objective"]}],"nextActions":["attach-action-source-objective","regenerate-planning-problem"]}
    """.utf8)

    try await createBlockedApprovalRun(root: root, runID: "run-1")
    try writeRunArtifact(
        payload,
        path: auditPath,
        artifactID: "planning-problem-translation-audit",
        root: root,
        runID: "run-1"
    )

    let json = try DesignFlowCLICommand.run(
        arguments: [
            "review-run",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let bundle = try JSONDecoder().decode(FlowRunReviewBundle.self, from: data)

    let item = try #require(bundle.reviewItems.first {
        $0.kind == .planningCorrectness
            && $0.itemID == "planning-problem-translation-audit-blocking"
    })
    #expect(item.status == .needsRepair)
    #expect(item.severity == .error)
    #expect(item.reason == "Candidate action action-1 has no valid source objective.")
    #expect(item.diagnosticCodes == ["orphan-candidate-action"])
    #expect(item.artifactPaths == [auditPath])
    #expect(item.nextActionID == "attach-action-source-objective")
}

}

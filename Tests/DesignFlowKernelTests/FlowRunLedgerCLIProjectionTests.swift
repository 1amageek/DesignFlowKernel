import Foundation
import Testing
import ToolQualification
import DesignFlowKernel

extension FlowRunLedgerSummaryTests {
@Test func inspectorEmitsSummary() async throws {
    let root = try makeTemporaryRoot("agent-summary-cli")
    defer { removeTemporaryRoot(root) }

    _ = try await makeTestOrchestrator(projectRoot: root).run(
        request: FlowOperationRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            intent: "Run preflight",
            stages: [
                FlowStageDefinition(stageID: "001-preflight", displayName: "Preflight"),
            ]
        ),
        toolRegistry: ToolRegistry(),
        healthResults: [:],
        executors: [
            SummaryStageExecutor(stageID: "001-preflight", toolID: "preflight-tool", status: .succeeded),
        ]
    )

    let summary = try await makeTestLedgerInspector(projectRoot: root).inspectRun(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(summary.runID == "run-1")
    #expect(summary.status == .succeeded)
    #expect(summary.stages.map(\.stageID) == ["001-preflight"])
    #expect(summary.nextActions.map(\.kind) == ["archiveOrContinue"])
}

@Test func inspectorEmitsSelectedSuggestedCommand() async throws {
    let root = try makeTemporaryRoot("agent-summary-selected-command-cli")
    defer { removeTemporaryRoot(root) }

    _ = try await makeTestOrchestrator(projectRoot: root).run(
        request: FlowOperationRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            intent: "Run preflight",
            stages: [
                FlowStageDefinition(stageID: "001-preflight", displayName: "Preflight"),
            ]
        ),
        toolRegistry: ToolRegistry(),
        healthResults: [:],
        executors: [
            SummaryStageExecutor(stageID: "001-preflight", toolID: "preflight-tool", status: .succeeded),
        ]
    )
    try await TestFlowInfrastructure.bound(to: root).appendRunAction(
        FlowRunActionRecord(
            actionID: "selection-1",
            runID: "run-1",
            actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
            actionKind: FlowSuggestedCommandSelection.actionKind,
            status: .succeeded,
            context: FlowRunActionContext(
                suggestedCommand: FlowRunActionContext.SuggestedCommand(
                    nextActionID: "verify-candidate-plan:post-execution",
                    nextActionKind: "verifyPlanningCorrectness",
                    commandID: "xcircuite-flow.verify-candidate-plan.post-execution",
                    readiness: "ready",
                    executable: "xcircuite-flow",
                    arguments: ["verify-candidate-plan", "--mode", "post-execution"],
                    reason: "Run post-execution candidate-plan verification."
                )
            )
        ),
        inProjectAt: root
    )

    let summary = try await makeTestLedgerInspector(projectRoot: root).inspectRun(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )
    let selection = try #require(summary.suggestedCommandSelections.first)

    #expect(summary.suggestedCommandSelections.count == 1)
    #expect(selection.actionRecordID == "selection-1")
    #expect(selection.actor.identifier == "reviewer-1")
    #expect(selection.nextActionID == "verify-candidate-plan:post-execution")
    #expect(selection.commandID == "xcircuite-flow.verify-candidate-plan.post-execution")
    #expect(selection.executable == "xcircuite-flow")
    #expect(selection.arguments == ["verify-candidate-plan", "--mode", "post-execution"])
}

@Test func inspectorEmitsPlanningCorrectnessNextAction() async throws {
    let root = try makeTemporaryRoot("agent-summary-planning-correctness-cli")
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
    let reference = try await TestFlowInfrastructure.bound(to: root).fileReference(
        forProjectRelativePath: planVerificationPath,
        artifactID: "planning-plan-verification",
        kind: .other,
        format: .json,
        inProjectAt: root,
        producerRunID: "run-1"
    )
    try await TestFlowInfrastructure.bound(to: root).upsertRunArtifact(reference, runID: "run-1", inProjectAt: root)

    let summary = try await makeTestLedgerInspector(projectRoot: root).inspectRun(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    let action = try #require(summary.nextActions.first {
        $0.kind == "repairPlanningCorrectness"
            && $0.actionID == "repair-planning-problem-goals"
    })
    #expect(action.severity == .warning)
    #expect(action.diagnosticCodes == ["missing-goal-atoms"])
    let command = try #require(action.suggestedCommands.first)
    #expect(command.commandID == "xcircuite-flow.validate-planning-problem.after-goal-edit")
    #expect(command.readiness == .requiresInput)
    #expect(command.executable == "xcircuite-flow")
    #expect(command.arguments == [
        "validate-planning-problem",
        "--workspace-id",
        try testWorkspaceID(for: root).rawValue,
        "--run-id",
        "run-1",
        "--pretty",
    ])
}

@Test func inspectorEmitsProblemTranslationAuditNextAction() async throws {
    let root = try makeTemporaryRoot("agent-summary-problem-translation-audit-cli")
    defer { removeTemporaryRoot(root) }
    let auditPath = ".xcircuite/runs/run-1/planning/problem-translation-audit.json"
    let payload = Data("""
    {"schemaVersion":1,"status":"failed","problemID":"problem-1","blocking":true,"diagnostics":[{"severity":"error","code":"orphan-objective","message":"Objective objective-1 has no valid source ref.","nextActions":["attach-objective-source-ref"]}],"nextActions":["attach-objective-source-ref","regenerate-planning-problem"]}
    """.utf8)

    try await createBlockedApprovalRun(root: root, runID: "run-1")
    try await writeRunArtifact(
        payload,
        path: auditPath,
        artifactID: "planning-problem-translation-audit",
        root: root,
        runID: "run-1"
    )

    let summary = try await makeTestLedgerInspector(projectRoot: root).inspectRun(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    let action = try #require(summary.nextActions.first {
        $0.kind == "repairProblemTranslationAudit"
            && $0.actionID == "attach-objective-source-ref"
    })
    #expect(action.severity == .error)
    #expect(action.reason == "Objective objective-1 has no valid source ref.")
    #expect(action.diagnosticCodes == ["orphan-objective"])
    let command = try #require(action.suggestedCommands.first)
    #expect(command.commandID == "xcircuite-flow.audit-problem-translation.after-translation-repair")
    #expect(command.readiness == .requiresInput)
    #expect(command.executable == "xcircuite-flow")
    #expect(command.arguments == [
        "audit-problem-translation",
        "--workspace-id",
        try testWorkspaceID(for: root).rawValue,
        "--run-id",
        "run-1",
        "--pretty",
    ])
}

@Test func flowRunNextActionRejectsMissingSuggestedCommands() throws {
    let payload = Data("""
    {"actionID":"incomplete-action","kind":"inspectFailure","severity":"warning","reason":"Incomplete next action.","diagnosticCodes":["incomplete-code"]}
    """.utf8)

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(FlowRunNextAction.self, from: payload)
    }
}

@Test func flowRunLedgerSummaryRejectsIncompleteCurrentSchema() throws {
    let payload = Data("""
    {"schemaVersion":1,"runID":"run-1","status":"succeeded","runDirectoryPath":"/tmp/run-1","stages":[],"actionCount":0,"approvalCount":0,"diagnostics":[],"nextActions":[]}
    """.utf8)

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(FlowRunLedgerSummary.self, from: payload)
    }
}

@Test func reviewBundlerEmitsReviewBundle() async throws {
    let root = try makeTemporaryRoot("agent-review-cli")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let bundle = try await makeTestReviewBundler(projectRoot: root).makeReviewBundle(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(bundle.runID == "run-1")
    #expect(bundle.reviewItems.contains {
        $0.kind == .approvalGate && $0.status == .needsReview
    })
    #expect(bundle.artifacts.contains {
        $0.purpose == .runManifest
    })
}

}

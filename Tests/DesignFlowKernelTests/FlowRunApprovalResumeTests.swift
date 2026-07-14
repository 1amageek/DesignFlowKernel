import DesignFlowKernel
import DesignFlowCLISupport
import Foundation
import Testing
import ToolQualification
import DesignFlowKernel

extension FlowRunLedgerSummaryTests {
@Test func approvalRecorderWritesDecisionAndSummarySuggestsResume() async throws {
    let root = try makeTemporaryRoot("agent-approval-api")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let result = try DefaultFlowGateApprovalRecorder().recordApproval(
        FlowGateApprovalRequest(
            projectRoot: root,
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1",
            note: "DRC report reviewed."
        )
    )

    #expect(result.approval.verdict == .approved)
    #expect(result.approval.reviewer == "reviewer-1")
    #expect(result.approval.planSHA256 != nil)
    #expect(result.approval.planByteCount != nil)
    #expect(result.approval.stageResultSHA256 != nil)
    #expect(result.approval.stageResultByteCount != nil)
    #expect(result.summary.approvalCount == 1)
    #expect(result.summary.nextActions.contains {
        $0.kind == "resumeRun" && $0.stageID == "001-drc"
    })
    #expect(!result.summary.nextActions.contains { $0.kind == "decideApproval" })

    let persistedApproval = try XcircuiteWorkspaceStore().loadApproval(
        runID: "run-1",
        stageID: "001-drc",
        inProjectAt: root
    )
    let persisted = try #require(persistedApproval)
    #expect(persisted.verdict == .approved)
    #expect(persisted.note == "DRC report reviewed.")

    let actions = try XcircuiteWorkspaceStore().loadRunActions(runID: "run-1", inProjectAt: root)
    let approvalAction = try #require(actions.first {
        $0.actionKind == XcircuiteRunReviewDecisionActionKind.approval.rawValue
    })
    #expect(approvalAction.actor.kind == .human)
    #expect(approvalAction.actor.identifier == "reviewer-1")
    #expect(approvalAction.metadata["source"] == .string("design-flow.approve-gate"))
    #expect(approvalAction.metadata["decision"] == .string("approved"))
    #expect(approvalAction.outputs.map(\.path) == [".xcircuite/runs/run-1/approvals/001-drc.json"])

    let manifest = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
    )
    #expect(manifest.artifacts.contains {
        $0.path == ".xcircuite/runs/run-1/approvals/001-drc.json"
            && $0.sha256 != nil
            && $0.byteCount != nil
    })
}

@Test func approveGateCLICommandEmitsResultJSON() async throws {
    let root = try makeTemporaryRoot("agent-approval-cli")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let json = try DesignFlowCLICommand.run(
        arguments: [
            "approve-gate",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
            "--stage-id",
            "001-drc",
            "--verdict",
            "rejected",
            "--reviewer",
            "reviewer-1",
            "--note",
            "Spacing violation still needs repair.",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(FlowGateApprovalResult.self, from: data)

    #expect(result.approval.verdict == .rejected)
    #expect(result.approval.stageID == "001-drc")
    #expect(result.approval.planSHA256 != nil)
    #expect(result.approval.stageResultSHA256 != nil)
    #expect(result.summary.approvalCount == 1)
    #expect(result.summary.nextActions.contains {
        $0.kind == "resumeRun" && $0.stageID == "001-drc"
    })
}

@Test func approveGateCLIRecordsAgentReviewerKind() async throws {
    let root = try makeTemporaryRoot("agent-approval-cli-actor-kind")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let json = try DesignFlowCLICommand.run(
        arguments: [
            "approve-gate",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
            "--stage-id",
            "001-drc",
            "--verdict",
            "approved",
            "--reviewer",
            "design-loop-agent",
            "--reviewer-kind",
            "agent",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(FlowGateApprovalResult.self, from: data)
    #expect(result.approval.reviewerKind == .agent)
    #expect(result.approval.reviewer == "design-loop-agent")

    let actions = try XcircuiteWorkspaceStore().loadRunActions(runID: "run-1", inProjectAt: root)
    let approvalAction = try #require(actions.first {
        $0.actionKind == XcircuiteRunReviewDecisionActionKind.approval.rawValue
    })
    #expect(approvalAction.actor.kind == .agent)
    #expect(approvalAction.actor.identifier == "design-loop-agent")
}

@Test func approveGateCLIRejectsUnknownReviewerKind() async throws {
    let root = try makeTemporaryRoot("agent-approval-cli-bad-actor-kind")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    #expect(throws: DesignFlowCLIError.self) {
        _ = try DesignFlowCLICommand.run(
            arguments: [
                "approve-gate",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-1",
                "--stage-id",
                "001-drc",
                "--verdict",
                "approved",
                "--reviewer",
                "design-loop-agent",
                "--reviewer-kind",
                "robot",
            ]
        )
    }
}

@Test func approvalRecorderRejectsStageWithoutApprovalGate() async throws {
    let root = try makeTemporaryRoot("agent-approval-no-gate")
    defer { removeTemporaryRoot(root) }

    _ = try await DefaultFlowOrchestrator().run(
        request: FlowOperationRequest(
            projectRoot: root,
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

    #expect(throws: FlowGateApprovalError.self) {
        try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: root,
                runID: "run-1",
                stageID: "001-preflight",
                verdict: .approved,
                reviewer: "reviewer-1"
            )
        )
    }
}

@Test func resumerReplaysPersistedPlanAfterApproval() async throws {
    let root = try makeTemporaryRoot("agent-resume-approved")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let ledger = try FlowRunLedgerLoader().loadRunLedger(runID: "run-1", projectRoot: root)
    #expect(ledger.plan?.intent == "Run DRC with human review")
    #expect(ledger.plan?.stages.map(\.stageID) == ["001-drc"])

    _ = try DefaultFlowGateApprovalRecorder().recordApproval(
        FlowGateApprovalRequest(
            projectRoot: root,
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )

    let descriptor = drcDescriptor()
    let resumed = try await DefaultFlowRunResumer().resumeRun(
        request: FlowRunResumeRequest(projectRoot: root, runID: "run-1"),
        toolRegistry: ToolRegistry(descriptors: [descriptor]),
        healthResults: [
            descriptor.toolID: ToolHealthCheckResult(
                toolID: descriptor.toolID,
                status: .passed,
                evidence: [qualifiedCorpusEvidence()]
            ),
        ],
        executors: [
            SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
        ]
    )

    #expect(resumed.result.status == .succeeded)
    #expect(resumed.summary.status == .succeeded)
    #expect(resumed.summary.approvalCount == 1)
    #expect(resumed.summary.stages.first?.gates.contains {
        $0.gateID == "approval" && $0.status == .passed
    } == true)
    #expect(resumed.summary.nextActions.map(\.kind) == ["archiveOrContinue"])
}

@Test func midFlowBlockedRunLoadsApprovesAndResumesRemainingStages() async throws {
    let root = try makeTemporaryRoot("agent-resume-mid-flow-block")
    defer { removeTemporaryRoot(root) }

    // Approval gate on the FIRST of two stages: the orchestrator blocks
    // before the second stage ever runs, so the ledger legitimately
    // holds a one-stage prefix of the two-stage plan.
    let descriptor = drcDescriptor()
    let health = [
        descriptor.toolID: ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: .passed,
            evidence: [qualifiedCorpusEvidence()]
        ),
    ]
    let executors: [any FlowStageExecutor] = [
        SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
        SummaryStageExecutor(stageID: "002-drc", toolID: "native-drc", status: .succeeded),
    ]
    let blocked = try await DefaultFlowOrchestrator().run(
        request: FlowOperationRequest(
            projectRoot: root,
            runID: "run-1",
            intent: "Run DRC with early human review",
            stages: [
                FlowStageDefinition(
                    stageID: "001-drc",
                    displayName: "DRC",
                    requiredTool: drcRequirement(),
                    requiresApproval: true
                ),
                FlowStageDefinition(
                    stageID: "002-drc",
                    displayName: "DRC follow-up",
                    requiredTool: drcRequirement()
                ),
            ]
        ),
        toolRegistry: ToolRegistry(descriptors: [descriptor]),
        healthResults: health,
        executors: executors
    )
    #expect(blocked.status == .blocked)
    #expect(blocked.stages.map(\.stageID) == ["001-drc"])

    // The interrupted ledger must stay readable: approval and resume both
    // load it before acting.
    let ledger = try FlowRunLedgerLoader().loadRunLedger(runID: "run-1", projectRoot: root)
    #expect(ledger.stages.map(\.stageID) == ["001-drc"])

    _ = try DefaultFlowGateApprovalRecorder().recordApproval(
        FlowGateApprovalRequest(
            projectRoot: root,
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "design-loop-agent",
            reviewerKind: .agent
        )
    )

    let resumed = try await DefaultFlowRunResumer().resumeRun(
        request: FlowRunResumeRequest(projectRoot: root, runID: "run-1"),
        toolRegistry: ToolRegistry(descriptors: [descriptor]),
        healthResults: health,
        executors: executors
    )
    #expect(resumed.result.status == .succeeded)
    #expect(resumed.result.stages.map(\.stageID) == ["001-drc", "002-drc"])
}

@Test func ledgerLoaderRejectsStageResultGapInInterruptedRun() async throws {
    let root = try makeTemporaryRoot("agent-ledger-gap")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    // Rewrite the plan to claim an earlier stage that has no result:
    // the recorded results no longer form a prefix of the plan, which
    // means evidence is missing, not that the run stopped early.
    let store = XcircuiteWorkspaceStore()
    let planURL = root.appending(path: ".xcircuite/runs/run-1/plan.json")
    var plan = try store.readJSON(FlowRunPlan.self, from: planURL)
    plan.stages.insert(
        FlowStageDefinition(stageID: "000-preflight", displayName: "Preflight"),
        at: 0
    )
    let data = try JSONEncoder().encode(plan)
    try data.write(to: planURL, options: .atomic)

    #expect(throws: XcircuiteWorkspaceError.self) {
        _ = try FlowRunLedgerLoader().loadRunLedger(runID: "run-1", projectRoot: root)
    }
}

@Test func approvalRecordBindsReviewedPlanAndStageResult() async throws {
    let root = try makeTemporaryRoot("agent-approval-binding")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    _ = try DefaultFlowGateApprovalRecorder().recordApproval(
        FlowGateApprovalRequest(
            projectRoot: root,
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )

    let approval = try #require(
        try XcircuiteWorkspaceStore().loadApproval(
            runID: "run-1",
            stageID: "001-drc",
            inProjectAt: root
        )
    )
    let planURL = root.appending(path: ".xcircuite/runs/run-1/plan.json")
    let resultURL = root.appending(path: ".xcircuite/runs/run-1/stages/001-drc/result.json")
    #expect(approval.planSHA256 == (try XcircuiteHasher().sha256(fileAt: planURL)))
    #expect(approval.planByteCount == (try XcircuiteHasher().byteCount(fileAt: planURL)))
    #expect(approval.stageResultSHA256 == (try XcircuiteHasher().sha256(fileAt: resultURL)))
    #expect(approval.stageResultByteCount == (try XcircuiteHasher().byteCount(fileAt: resultURL)))
}

@Test func resumerRejectsTamperedPersistedPlan() async throws {
    let root = try makeTemporaryRoot("agent-resume-tampered-plan")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    _ = try DefaultFlowGateApprovalRecorder().recordApproval(
        FlowGateApprovalRequest(
            projectRoot: root,
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )
    try XcircuiteWorkspaceStore().writeJSON(
        FlowRunPlan(
            runID: "run-1",
            intent: "Tampered intent",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
            ]
        ),
        to: root.appending(path: ".xcircuite/runs/run-1/plan.json"),
        forProjectAt: root
    )

    let descriptor = drcDescriptor()
    await #expect(throws: FlowRunResumeError.self) {
        try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: root, runID: "run-1"),
            toolRegistry: ToolRegistry(descriptors: [descriptor]),
            healthResults: [
                descriptor.toolID: ToolHealthCheckResult(
                    toolID: descriptor.toolID,
                    status: .passed,
                    evidence: [qualifiedCorpusEvidence()]
                ),
            ],
            executors: [
                SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
            ]
        )
    }
}

@Test func staleApprovalBlocksResumeWhenReviewedStageResultChanges() async throws {
    let root = try makeTemporaryRoot("agent-resume-stale-approval")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    _ = try DefaultFlowGateApprovalRecorder().recordApproval(
        FlowGateApprovalRequest(
            projectRoot: root,
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )
    try Data(#"{"stageID":"001-drc","status":"blocked","diagnostics":[{"severity":"warning","code":"TAMPERED","message":"tampered"}],"gates":[],"artifacts":[],"attempts":[]}"#.utf8)
        .write(to: root.appending(path: ".xcircuite/runs/run-1/stages/001-drc/result.json"), options: .atomic)

    let descriptor = drcDescriptor()
    let resumed = try await DefaultFlowRunResumer().resumeRun(
        request: FlowRunResumeRequest(projectRoot: root, runID: "run-1"),
        toolRegistry: ToolRegistry(descriptors: [descriptor]),
        healthResults: [
            descriptor.toolID: ToolHealthCheckResult(
                toolID: descriptor.toolID,
                status: .passed,
                evidence: [qualifiedCorpusEvidence()]
            ),
        ],
        executors: [
            SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
        ]
    )

    #expect(resumed.result.status == .blocked)
    #expect(resumed.result.stages.first?.gates.contains {
        $0.gateID == "approval" && $0.status == .incomplete
    } == true)
    #expect(resumed.result.stages.first?.diagnostics.contains {
        $0.code == "APPROVAL_BINDING_MISMATCH"
    } == true)
}

@Test func approvalRecordedDuringExecutionMustMatchCurrentStageResult() async throws {
    let root = try makeTemporaryRoot("agent-approval-during-execution")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let descriptor = drcDescriptor()
    let result = try await DefaultFlowOrchestrator().run(
        request: FlowOperationRequest(
            projectRoot: root,
            runID: "run-1",
            intent: "Run DRC with human review",
            stages: [
                FlowStageDefinition(
                    stageID: "001-drc",
                    displayName: "DRC",
                    requiredTool: drcRequirement(requiredEvidenceKinds: [.corpus]),
                    requiresApproval: true
                ),
            ],
            allowExistingRunDirectory: true
        ),
        toolRegistry: ToolRegistry(descriptors: [descriptor]),
        healthResults: [
            descriptor.toolID: ToolHealthCheckResult(
                toolID: descriptor.toolID,
                status: .passed,
                evidence: [qualifiedCorpusEvidence()]
            ),
        ],
        executors: [
            ApprovalDuringExecutionExecutor(stageID: "001-drc", toolID: "native-drc"),
        ]
    )

    #expect(result.status == .blocked)
    #expect(result.stages.first?.gates.contains {
        $0.gateID == "approval" && $0.status == .incomplete
    } == true)
    #expect(result.stages.first?.diagnostics.contains {
        $0.code == "APPROVAL_BINDING_MISMATCH"
    } == true)
}

@Test func resumerRejectsSucceededRuns() async throws {
    let root = try makeTemporaryRoot("agent-resume-succeeded")
    defer { removeTemporaryRoot(root) }

    _ = try await DefaultFlowOrchestrator().run(
        request: FlowOperationRequest(
            projectRoot: root,
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

    await #expect(throws: FlowRunResumeError.self) {
        try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: root, runID: "run-1"),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                SummaryStageExecutor(stageID: "001-preflight", toolID: "preflight-tool", status: .succeeded),
            ]
        )
    }
}

@Test func resumerRetriesFailedRunWithRepairedExecutor() async throws {
    let root = try makeTemporaryRoot("agent-resume-failed-retry")
    defer { removeTemporaryRoot(root) }

    // First attempt: stage 2 fails mid-flow, leaving a one-stage-deep
    // failure ledger behind.
    let stages = [
        FlowStageDefinition(stageID: "001-prepare", displayName: "Prepare"),
        FlowStageDefinition(stageID: "002-verify", displayName: "Verify"),
    ]
    let failed = try await DefaultFlowOrchestrator().run(
        request: FlowOperationRequest(
            projectRoot: root,
            runID: "run-1",
            intent: "Retry after repair",
            stages: stages
        ),
        toolRegistry: ToolRegistry(),
        healthResults: [:],
        executors: [
            SummaryStageExecutor(stageID: "001-prepare", toolID: "prepare-tool", status: .succeeded),
            SummaryStageExecutor(stageID: "002-verify", toolID: "verify-tool", status: .failed),
        ]
    )
    #expect(failed.status == .failed)

    // Retry resumes the SAME persisted plan with a repaired executor;
    // the failed stage result is superseded in place.
    let resumed = try await DefaultFlowRunResumer().resumeRun(
        request: FlowRunResumeRequest(projectRoot: root, runID: "run-1"),
        toolRegistry: ToolRegistry(),
        healthResults: [:],
        executors: [
            SummaryStageExecutor(stageID: "001-prepare", toolID: "prepare-tool", status: .succeeded),
            SummaryStageExecutor(stageID: "002-verify", toolID: "verify-tool", status: .succeeded),
        ]
    )
    #expect(resumed.result.status == .succeeded)
    #expect(resumed.result.stages.map(\.stageID) == ["001-prepare", "002-verify"])
    #expect(resumed.summary.status == .succeeded)
}

@Test func resumerRejectsCancelledRuns() async throws {
    let root = try makeTemporaryRoot("agent-resume-cancelled")
    defer { removeTemporaryRoot(root) }

    // Cancellation is an explicit human stop and must stay final even
    // though a blocked run would otherwise be resumable.
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    let store = XcircuiteWorkspaceStore()
    _ = try store.transitionRun(
        runID: "run-1",
        transition: XcircuiteRunTransition(status: .cancelled),
        inProjectAt: root
    )

    await #expect(throws: FlowRunResumeError.self) {
        try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: root, runID: "run-1"),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
            ]
        )
    }
}

@Test func rerunWithExistingRunIDIsRejectedByDefault() async throws {
    let root = try makeTemporaryRoot("agent-rerun-duplicate-run-id")
    defer { removeTemporaryRoot(root) }
    let path = ".xcircuite/runs/run-1/reports/drc-summary.json"
    let oldPayload = Data(#"{"version":1}"#.utf8)
    let reference = XcircuiteFileReference(
        artifactID: "drc-summary",
        path: path,
        kind: .report,
        format: .json,
        producedByRunID: "run-1"
    )
    let request = FlowOperationRequest(
        projectRoot: root,
        runID: "run-1",
        intent: "Run DRC",
        stages: [
            FlowStageDefinition(stageID: "001-drc", displayName: "DRC"),
        ]
    )

    _ = try await DefaultFlowOrchestrator().run(
        request: request,
        toolRegistry: ToolRegistry(),
        healthResults: [:],
        executors: [
            SummaryStageExecutor(
                stageID: "001-drc",
                toolID: "native-drc",
                status: .succeeded,
                artifacts: [reference],
                artifactPayloads: [path: oldPayload]
            ),
        ]
    )
    await #expect(throws: FlowExecutionError.self) {
        try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                SummaryStageExecutor(
                    stageID: "001-drc",
                    toolID: "native-drc",
                    status: .succeeded,
                    artifacts: [reference],
                    artifactPayloads: [path: Data(#"{"version":2}"#.utf8)]
                ),
            ]
        )
    }
}

@Test func allowExistingRunDirectoryRejectsMismatchedExistingPlan() async throws {
    let root = try makeTemporaryRoot("agent-rerun-existing-plan-mismatch")
    defer { removeTemporaryRoot(root) }
    let request = FlowOperationRequest(
        projectRoot: root,
        runID: "run-1",
        intent: "Run DRC",
        stages: [
            FlowStageDefinition(stageID: "001-drc", displayName: "DRC"),
        ]
    )

    _ = try await DefaultFlowOrchestrator().run(
        request: request,
        toolRegistry: ToolRegistry(),
        healthResults: [:],
        executors: [
            SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
        ]
    )
    let planURL = root.appending(path: ".xcircuite/runs/run-1/plan.json")
    let originalPlanData = try Data(contentsOf: planURL)
    let mismatchedRequest = FlowOperationRequest(
        projectRoot: root,
        runID: "run-1",
        intent: "Run LVS instead",
        stages: [
            FlowStageDefinition(stageID: "001-lvs", displayName: "LVS"),
        ],
        allowExistingRunDirectory: true
    )

    do {
        _ = try await DefaultFlowOrchestrator().run(
            request: mismatchedRequest,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                SummaryStageExecutor(stageID: "001-lvs", toolID: "native-lvs", status: .succeeded),
            ]
        )
        Issue.record("Expected existing run plan mismatch to be rejected")
    } catch let error as FlowExecutionError {
        #expect(error == .existingRunPlanMismatch("run-1"))
    } catch {
        throw error
    }

    let currentPlanData = try Data(contentsOf: planURL)
    #expect(currentPlanData == originalPlanData)
    #expect(!FileManager.default.fileExists(
        atPath: root.appending(path: ".xcircuite/runs/run-1/stages/001-lvs/result.json")
            .path(percentEncoded: false)
    ))
}

@Test func resumePreservesRunLevelArtifacts() async throws {
    let root = try makeTemporaryRoot("agent-resume-artifacts")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    try XcircuiteWorkspaceStore().writeDesignDiff(
        XcircuiteDesignDiff(
            runID: "run-1",
            title: "DRC repair proposal",
            actor: "agent-1",
            changes: [
                XcircuiteDesignDiffChange(
                    changeID: "change-1",
                    domain: .layout,
                    operation: .replace,
                    path: "/cells/INV/layout/shapes/met1/rail",
                    before: .object(["width": .number(0.14)]),
                    after: .object(["width": .number(0.20)]),
                    summary: "Widen the met1 rail before approval."
                ),
            ]
        ),
        inProjectAt: root
    )
    _ = try DefaultFlowGateApprovalRecorder().recordApproval(
        FlowGateApprovalRequest(
            projectRoot: root,
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )

    let descriptor = drcDescriptor()
    _ = try await DefaultFlowRunResumer().resumeRun(
        request: FlowRunResumeRequest(projectRoot: root, runID: "run-1"),
        toolRegistry: ToolRegistry(descriptors: [descriptor]),
        healthResults: [
            descriptor.toolID: ToolHealthCheckResult(
                toolID: descriptor.toolID,
                status: .passed,
                evidence: [qualifiedCorpusEvidence()]
            ),
        ],
        executors: [
            SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
        ]
    )

    let manifest = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
    )
    #expect(manifest.artifacts.contains {
        $0.path == ".xcircuite/runs/run-1/design-diff.json"
    })
    #expect(manifest.artifacts.contains {
        $0.path == ".xcircuite/runs/run-1/plan.json"
    })
}

@Test func resumerRejectsRunsWithoutPersistedPlan() async throws {
    let root = try makeTemporaryRoot("agent-resume-missing-plan")
    defer { removeTemporaryRoot(root) }
    try XcircuiteWorkspaceStore().createWorkspace(at: root)
    try XcircuiteWorkspaceStore().createRunDirectory(for: "run-1", inProjectAt: root)

    await #expect(throws: FlowRunResumeError.self) {
        try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: root, runID: "run-1"),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: []
        )
    }
}

}

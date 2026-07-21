import DesignFlowKernel
import CircuiteFoundation
import Foundation
import Testing
import ToolQualification
import DesignFlowKernel

extension FlowRunLedgerSummaryTests {
@Test func approvalRecorderWritesDecisionAndSummarySuggestsResume() async throws {
    let root = try makeTemporaryRoot("agent-approval-api")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let result = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1",
            note: "DRC report reviewed."
        )
    )

    #expect(result.approval.verdict == .approved)
    #expect(result.approval.reviewer == "reviewer-1")
    #expect(!result.approval.evidence.plan.digest.hexadecimalValue.isEmpty)
    #expect(result.approval.evidence.plan.byteCount > 0)
    #expect(!result.approval.evidence.stageResult.digest.hexadecimalValue.isEmpty)
    #expect(result.approval.evidence.stageResult.byteCount > 0)
    #expect(result.summary.approvalCount == 1)
    #expect(result.summary.nextActions.contains {
        $0.kind == "resumeRun" && $0.stageID == "001-drc"
    })
    #expect(!result.summary.nextActions.contains { $0.kind == "decideApproval" })

    let persistedApproval = try await TestFlowInfrastructure.bound(to: root).loadApproval(
        runID: "run-1",
        stageID: "001-drc",
        inProjectAt: root
    )
    let persisted = try #require(persistedApproval)
    #expect(persisted.verdict == .approved)
    #expect(persisted.note == "DRC report reviewed.")

    let persistedLedger = try await TestFlowInfrastructure.bound(to: root).loadRunLedger(runID: "run-1")
    #expect(persistedLedger.approvals == [persisted])
    #expect(persisted.evidence.plan.artifactID == "run-plan")
    #expect(persisted.evidence.stageResult.artifactID == "approval-review-001-drc")
    #expect(
        persisted.evidence.stageResult.path
            == ".xcircuite/runs/run-1/review/approval-inputs/001-drc-"
                + persisted.evidence.stageResult.digest.hexadecimalValue
                + ".json"
    )
    let action = try #require(persistedLedger.actions.last {
        $0.actionKind == FlowRunReviewDecisionKind.approval.rawValue
    })
    #expect(action.outputs.count == 1)
    let approvalReference = try #require(action.outputs.first)
    #expect(action.inputs == [persisted.evidence.plan, persisted.evidence.stageResult])
    #expect(approvalReference.artifactID == "approval-001-drc")
    #expect(approvalReference.locator.role == .output)
    #expect(approvalReference.locator.kind == .report)
    #expect(approvalReference.locator.format == .json)
    let content = try await TestFlowInfrastructure.bound(to: root).loadArtifactContent(
        for: approvalReference
    )
    #expect(try JSONDecoder().decode(FlowApprovalRecord.self, from: content) == persisted)
}

@Test func approvalRecorderRejectsDuplicateStageDecision() async throws {
    let root = try makeTemporaryRoot("agent-approval-duplicate")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    let recorder = await makeTestApprovalRecorder(projectRoot: root)
    let request = FlowGateApprovalRequest(
        workspaceID: try testWorkspaceID(for: root),
        runID: "run-1",
        stageID: "001-drc",
        verdict: .approved,
        reviewer: "reviewer-1"
    )
    _ = try await recorder.recordApproval(request)

    await #expect(throws: FlowRunLedgerPersistenceError.duplicateApprovalID(
        runID: "run-1",
        approvalID: "001-drc"
    )) {
        try await recorder.recordApproval(request)
    }
}

@Test func approvalRecorderRecoversAfterReviewedSnapshotWasRetained() async throws {
    let root = try makeTemporaryRoot("agent-approval-retention-retry")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    let infrastructure = await TestFlowInfrastructure.bound(to: root)
    let ledger = try await infrastructure.loadRunLedger(runID: "run-1")
    let resultReference = try #require(ledger.artifacts.first {
        $0.artifactID == "001-drc-result"
    })
    let resultContent = try await infrastructure.loadArtifactContent(for: resultReference)
    let digest = try SHA256ContentDigester().digest(data: resultContent)
    let snapshotReference = ArtifactReference(
        id: try ArtifactID(rawValue: "approval-review-001-drc"),
        locator: ArtifactLocator(
            location: try ArtifactLocation(
                workspaceRelativePath: ".xcircuite/runs/run-1/review/approval-inputs/001-drc-"
                    + digest.hexadecimalValue
                    + ".json"
            ),
            role: .output,
            kind: .report,
            format: .json
        ),
        digest: digest,
        byteCount: UInt64(resultContent.count)
    )
    let retentionAction = FlowRunActionRecord(
        actionID: "approval-review-001-drc-\(digest.hexadecimalValue)",
        runID: "run-1",
        stageID: "001-drc",
        actor: FlowRunActor(kind: .system, identifier: "design-flow-kernel"),
        actionKind: "approval.review.retain",
        status: .succeeded,
        inputs: [try #require(ledger.artifacts.first { $0.artifactID == "run-plan" })],
        outputs: [snapshotReference],
        createdAt: ledger.runManifest.finishedAt ?? ledger.runManifest.createdAt
    )
    _ = try await infrastructure.appendActionArtifact(
        content: resultContent,
        reference: snapshotReference,
        action: retentionAction
    )

    let result = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-after-restart",
            decidedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
    )

    #expect(result.approval.evidence.stageResult == snapshotReference)
    let persisted = try await infrastructure.loadRunLedger(runID: "run-1")
    #expect(persisted.actions.filter { $0.actionID == retentionAction.actionID }.count == 1)
    #expect(persisted.approvals.count == 1)
}

@Test func approvalArtifactDeletionIsReportedAsIntegrityFailure() async throws {
    let root = try makeTemporaryRoot("agent-approval-artifact-deleted")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )
    let store = await TestFlowInfrastructure.bound(to: root)
    let ledger = try await store.loadRunLedger(runID: "run-1")
    let reference = try #require(ledger.actions.last?.outputs.first)
    try FileManager.default.removeItem(at: approvalArtifactURL(reference, root: root))

    await #expect(throws: FlowRunLedgerPersistenceError.self) {
        _ = try await store.loadArtifactContent(for: reference)
    }
}

@Test func approvalArtifactModificationIsReportedAsIntegrityFailure() async throws {
    let root = try makeTemporaryRoot("agent-approval-artifact-modified")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )
    let store = await TestFlowInfrastructure.bound(to: root)
    let ledger = try await store.loadRunLedger(runID: "run-1")
    let reference = try #require(ledger.actions.last?.outputs.first)
    try Data(#"{"tampered":true}"#.utf8).write(
        to: approvalArtifactURL(reference, root: root),
        options: .atomic
    )

    await #expect(throws: FlowRunLedgerPersistenceError.self) {
        _ = try await store.loadArtifactContent(for: reference)
    }
}

private func approvalArtifactURL(_ reference: ArtifactReference, root: URL) -> URL {
    let path = reference.path.hasPrefix(".xcircuite/")
        ? reference.path
        : ".xcircuite/\(reference.path)"
    return root.appending(path: path)
}

private struct StaticFlowRunLedgerLoader: FlowRunLedgerLoading {
    let ledger: FlowRunLedger

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        guard runID == ledger.runID else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        }
        return ledger
    }
}

private func replacingManifestArtifacts(
    in manifest: FlowRunManifest,
    with artifacts: [ArtifactReference]
) throws -> FlowRunManifest {
    try FlowRunManifest(
        runID: manifest.runID,
        status: manifest.status,
        revision: manifest.revision + 1,
        actor: manifest.actor,
        intent: manifest.intent,
        parentRunID: manifest.parentRunID,
        createdAt: manifest.createdAt,
        updatedAt: max(Date(), manifest.updatedAt),
        startedAt: manifest.startedAt,
        finishedAt: manifest.finishedAt,
        artifacts: artifacts
    )
}

private func reference(
    replacingPath path: String,
    in reference: ArtifactReference
) throws -> ArtifactReference {
    ArtifactReference(
        id: reference.id,
        locator: ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: reference.locator.role,
            kind: reference.locator.kind,
            format: reference.locator.format
        ),
        digest: reference.digest,
        byteCount: reference.byteCount,
        producer: reference.producer
    )
}

@Test func approvalRecorderRejectsArbitraryArtifactPathPrefix() async throws {
    let root = try makeTemporaryRoot("agent-approval-evil-prefix")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    let infrastructure = await TestFlowInfrastructure.bound(to: root)
    var ledger = try await infrastructure.loadRunLedger(runID: "run-1")
    let originalPlan = try #require(ledger.artifacts.first { $0.artifactID == "run-plan" })
    let forgedPlan = try reference(
        replacingPath: "evil/runs/run-1/plan.json",
        in: originalPlan
    )
    ledger.artifacts.removeAll { $0.artifactID == "run-plan" }
    ledger.artifacts.append(forgedPlan)
    let recorder = DefaultFlowGateApprovalRecorder(
        loader: StaticFlowRunLedgerLoader(ledger: ledger),
        inspector: await makeTestLedgerInspector(projectRoot: root),
        approvalPersistence: infrastructure,
        artifactLocationValidator: DefaultFlowRunArtifactLocationValidator(
            storagePrefix: ".xcircuite"
        )
    )

    await #expect(throws: FlowGateApprovalError.evidenceArtifactNotFound(
        "runs/run-1/plan.json"
    )) {
        try await recorder.recordApproval(
            FlowGateApprovalRequest(
                workspaceID: try testWorkspaceID(for: root),
                runID: "run-1",
                stageID: "001-drc",
                verdict: .approved,
                reviewer: "reviewer-1"
            )
        )
    }
}

@Test func resumerRejectsArbitraryArtifactPathPrefix() async throws {
    let root = try makeTemporaryRoot("agent-resume-evil-prefix")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    let infrastructure = await TestFlowInfrastructure.bound(to: root)
    var ledger = try await infrastructure.loadRunLedger(runID: "run-1")
    let originalPlan = try #require(ledger.runManifest.artifacts.first {
        $0.artifactID == "run-plan"
    })
    let forgedPlan = try reference(
        replacingPath: "evil/runs/run-1/plan.json",
        in: originalPlan
    )
    var artifacts = ledger.runManifest.artifacts.filter { $0.artifactID != "run-plan" }
    artifacts.append(forgedPlan)
    ledger.runManifest = try replacingManifestArtifacts(
        in: ledger.runManifest,
        with: artifacts
    )
    let resumer = DefaultFlowRunResumer(
        loader: StaticFlowRunLedgerLoader(ledger: ledger),
        orchestrator: try await makeTestOrchestrator(projectRoot: root),
        inspector: await makeTestLedgerInspector(projectRoot: root),
        artifactPersistence: infrastructure,
        artifactLocationValidator: DefaultFlowRunArtifactLocationValidator(
            storagePrefix: ".xcircuite"
        )
    )

    await #expect(throws: FlowRunResumeError.missingPlanReference("run-1")) {
        try await resumer.resumeRun(
            request: FlowRunResumeRequest(
                workspaceID: try testWorkspaceID(for: root),
                runID: "run-1"
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: []
        )
    }
}

@Test func approvalRecorderReturnsRejectedDecisionAndResumeAction() async throws {
    let root = try makeTemporaryRoot("agent-approval-rejected")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let result = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .rejected,
            reviewer: "reviewer-1",
            note: "Spacing violation still needs repair."
        )
    )

    #expect(result.approval.verdict == .rejected)
    #expect(result.approval.stageID == "001-drc")
    #expect(result.approval.evidence.plan.byteCount > 0)
    #expect(result.approval.evidence.stageResult.byteCount > 0)
    #expect(result.summary.approvalCount == 1)
    #expect(result.summary.nextActions.contains {
        $0.kind == "resumeRun" && $0.stageID == "001-drc"
    })
}

@Test func approvalRecorderRecordsAgentReviewerKind() async throws {
    let root = try makeTemporaryRoot("agent-approval-actor-kind")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let result = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "design-loop-agent",
            reviewerKind: .agent
        )
    )
    #expect(result.approval.reviewerKind == .agent)
    #expect(result.approval.reviewer == "design-loop-agent")

    let persisted = try #require(
        try await TestFlowInfrastructure.bound(to: root).loadApproval(
            runID: "run-1",
            stageID: "001-drc"
        )
    )
    #expect(persisted.reviewerKind == .agent)
    #expect(persisted.reviewer == "design-loop-agent")
}

@Test func flowGateApprovalRequestRejectsUnknownReviewerKind() throws {
    let payload = Data("""
    {"projectRoot":"file:///tmp/project","runID":"run-1","stageID":"001-drc","verdict":"approved","reviewer":"design-loop-agent","reviewerKind":"robot","note":"","decidedAt":0}
    """.utf8)

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(FlowGateApprovalRequest.self, from: payload)
    }
}

@Test func approvalRecorderRejectsStageWithoutApprovalGate() async throws {
    let root = try makeTemporaryRoot("agent-approval-no-gate")
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

    await #expect(throws: FlowGateApprovalError.self) {
        try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
            FlowGateApprovalRequest(
                workspaceID: try testWorkspaceID(for: root),
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

    let ledger = try await TestFlowInfrastructure.bound(to: root).loadRunLedger(runID: "run-1")
    #expect(ledger.plan?.intent == "Run DRC with human review")
    #expect(ledger.plan?.stages.map(\.stageID) == ["001-drc"])

    _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )

    let qualification = try await TestToolQualificationFixtures.qualificationRecord(
        for: drcDescriptor(),
        projectRoot: root
    )
    let descriptor = qualification.descriptor
    let resumed = try await makeTestRunResumer(projectRoot: root).resumeRun(
        request: FlowRunResumeRequest(workspaceID: try testWorkspaceID(for: root), runID: "run-1"),
        toolRegistry: try ToolRegistry(descriptors: [descriptor]),
        healthResults: [descriptor.toolID: qualification.health],
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
    let qualification = try await TestToolQualificationFixtures.qualificationRecord(
        for: drcDescriptor(),
        projectRoot: root
    )
    let descriptor = qualification.descriptor
    let health = [descriptor.toolID: qualification.health]
    let executors: [any FlowStageExecutor] = [
        SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
        SummaryStageExecutor(stageID: "002-drc", toolID: "native-drc", status: .succeeded),
    ]
    let blocked = try await makeTestOrchestrator(projectRoot: root).run(
        request: FlowOperationRequest(
            workspaceID: try testWorkspaceID(for: root),
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
        toolRegistry: try ToolRegistry(descriptors: [descriptor]),
        healthResults: health,
        executors: executors
    )
    #expect(blocked.status == .blocked)
    #expect(blocked.stages.map(\.stageID) == ["001-drc"])

    // The interrupted ledger must stay readable: approval and resume both
    // load it before acting.
    let ledger = try await TestFlowInfrastructure.bound(to: root).loadRunLedger(runID: "run-1")
    #expect(ledger.stages.map(\.stageID) == ["001-drc"])

    _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "design-loop-agent",
            reviewerKind: .agent
        )
    )

    let resumed = try await makeTestRunResumer(projectRoot: root).resumeRun(
        request: FlowRunResumeRequest(workspaceID: try testWorkspaceID(for: root), runID: "run-1"),
        toolRegistry: try ToolRegistry(descriptors: [descriptor]),
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
    let store = await TestFlowInfrastructure.bound(to: root)
    let planURL = root.appending(path: ".xcircuite/runs/run-1/plan.json")
    var plan = try await store.readJSON(FlowRunPlan.self, from: planURL)
    plan.stages.insert(
        FlowStageDefinition(stageID: "000-preflight", displayName: "Preflight"),
        at: 0
    )
    let data = try JSONEncoder().encode(plan)
    try data.write(to: planURL, options: .atomic)

    await #expect(throws: FlowRunLedgerPersistenceError.self) {
        _ = try await TestFlowInfrastructure.bound(to: root).loadRunLedger(runID: "run-1")
    }
}

@Test func approvalRecordBindsReviewedPlanAndStageResult() async throws {
    let root = try makeTemporaryRoot("agent-approval-binding")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )

    let approval = try #require(
        try await TestFlowInfrastructure.bound(to: root).loadApproval(
            runID: "run-1",
            stageID: "001-drc",
            inProjectAt: root
        )
    )
    let planURL = root.appending(path: ".xcircuite/runs/run-1/plan.json")
    let resultURL = root.appending(path: ".xcircuite/runs/run-1/stages/001-drc/result.json")
    #expect(approval.evidence.plan.digest.hexadecimalValue == (try TestContentDigester().sha256(fileAt: planURL)))
    #expect(approval.evidence.plan.byteCount == UInt64(try TestContentDigester().byteCount(fileAt: planURL)))
    #expect(approval.evidence.stageResult.digest.hexadecimalValue == (try TestContentDigester().sha256(fileAt: resultURL)))
    #expect(approval.evidence.stageResult.byteCount == UInt64(try TestContentDigester().byteCount(fileAt: resultURL)))
}

@Test func resumerRejectsTamperedPersistedPlan() async throws {
    let root = try makeTemporaryRoot("agent-resume-tampered-plan")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )
    try await TestFlowInfrastructure.bound(to: root).writeJSON(
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

    let qualification = try await TestToolQualificationFixtures.qualificationRecord(
        for: drcDescriptor(),
        projectRoot: root
    )
    let descriptor = qualification.descriptor
    await #expect(throws: FlowRunResumeError.self) {
        try await makeTestRunResumer(projectRoot: root).resumeRun(
            request: FlowRunResumeRequest(workspaceID: try testWorkspaceID(for: root), runID: "run-1"),
            toolRegistry: try ToolRegistry(descriptors: [descriptor]),
            healthResults: [descriptor.toolID: qualification.health],
            executors: [
                SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
            ]
        )
    }
}

@Test func resumerRejectsLedgerPlanThatDiffersFromDigestBoundArtifact() async throws {
    let root = try makeTemporaryRoot("agent-resume-ledger-plan-mismatch")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let infrastructure = await TestFlowInfrastructure.bound(to: root)
    var ledger = try await infrastructure.loadRunLedger(runID: "run-1")
    let retainedPlan = try #require(ledger.plan)
    ledger.plan = FlowRunPlan(
        runID: retainedPlan.runID,
        intent: "Forged ledger intent",
        toolchainProfile: retainedPlan.toolchainProfile,
        stages: retainedPlan.stages
    )
    let resumer = DefaultFlowRunResumer(
        loader: StaticFlowRunLedgerLoader(ledger: ledger),
        orchestrator: try await makeTestOrchestrator(projectRoot: root),
        inspector: await makeTestLedgerInspector(projectRoot: root),
        artifactPersistence: infrastructure,
        artifactLocationValidator: DefaultFlowRunArtifactLocationValidator(
            storagePrefix: ".xcircuite"
        )
    )

    await #expect(throws: FlowRunResumeError.planProjectionMismatch("run-1")) {
        try await resumer.resumeRun(
            request: FlowRunResumeRequest(
                workspaceID: try testWorkspaceID(for: root),
                runID: "run-1"
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: []
        )
    }
}

@Test func staleApprovalBlocksResumeWhenReviewedStageResultChanges() async throws {
    let root = try makeTemporaryRoot("agent-resume-stale-approval")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )
    try Data(#"{"stageID":"001-drc","status":"blocked","diagnostics":[{"severity":"warning","code":"TAMPERED","message":"tampered"}],"gates":[],"artifacts":[],"attempts":[]}"#.utf8)
        .write(to: root.appending(path: ".xcircuite/runs/run-1/stages/001-drc/result.json"), options: .atomic)

    let qualification = try await TestToolQualificationFixtures.qualificationRecord(
        for: drcDescriptor(),
        projectRoot: root
    )
    let descriptor = qualification.descriptor
    let resumed = try await makeTestRunResumer(projectRoot: root).resumeRun(
        request: FlowRunResumeRequest(workspaceID: try testWorkspaceID(for: root), runID: "run-1"),
        toolRegistry: try ToolRegistry(descriptors: [descriptor]),
        healthResults: [descriptor.toolID: qualification.health],
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

    let qualification = try await TestToolQualificationFixtures.qualificationRecord(
        for: drcDescriptor(),
        projectRoot: root
    )
    let descriptor = qualification.descriptor
    let result = try await makeTestOrchestrator(projectRoot: root).run(
        request: FlowOperationRequest(
            workspaceID: try testWorkspaceID(for: root),
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
            allowExistingRun: true
        ),
        toolRegistry: try ToolRegistry(descriptors: [descriptor]),
        healthResults: [descriptor.toolID: qualification.health],
        executors: [
            ApprovalDuringExecutionExecutor(
                stageID: "001-drc",
                toolID: "native-drc",
                approvalRecorder: await makeTestApprovalRecorder(projectRoot: root)
            ),
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

    await #expect(throws: FlowRunResumeError.self) {
        try await makeTestRunResumer(projectRoot: root).resumeRun(
            request: FlowRunResumeRequest(workspaceID: try testWorkspaceID(for: root), runID: "run-1"),
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
    let failed = try await makeTestOrchestrator(projectRoot: root).run(
        request: FlowOperationRequest(
            workspaceID: try testWorkspaceID(for: root),
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
    let resumed = try await makeTestRunResumer(projectRoot: root).resumeRun(
        request: FlowRunResumeRequest(workspaceID: try testWorkspaceID(for: root), runID: "run-1"),
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
    let store = await TestFlowInfrastructure.bound(to: root)
    try await store.setRunStatus(.cancelled, runID: "run-1")

    await #expect(throws: FlowRunResumeError.self) {
        try await makeTestRunResumer(projectRoot: root).resumeRun(
            request: FlowRunResumeRequest(workspaceID: try testWorkspaceID(for: root), runID: "run-1"),
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
    let reference = TestArtifactReference(
        artifactID: "drc-summary",
        path: path,
        kind: .report,
        format: .json,
        producerRunID: "run-1"
    )
    let request = FlowOperationRequest(
        workspaceID: try testWorkspaceID(for: root),
        runID: "run-1",
        intent: "Run DRC",
        stages: [
            FlowStageDefinition(stageID: "001-drc", displayName: "DRC"),
        ]
    )

    _ = try await makeTestOrchestrator(projectRoot: root).run(
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
        try await makeTestOrchestrator(projectRoot: root).run(
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

@Test func allowExistingRunRejectsMismatchedExistingPlan() async throws {
    let root = try makeTemporaryRoot("agent-rerun-existing-plan-mismatch")
    defer { removeTemporaryRoot(root) }
    let request = FlowOperationRequest(
        workspaceID: try testWorkspaceID(for: root),
        runID: "run-1",
        intent: "Run DRC",
        stages: [
            FlowStageDefinition(stageID: "001-drc", displayName: "DRC"),
        ]
    )

    _ = try await makeTestOrchestrator(projectRoot: root).run(
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
        workspaceID: try testWorkspaceID(for: root),
        runID: "run-1",
        intent: "Run LVS instead",
        stages: [
            FlowStageDefinition(stageID: "001-lvs", displayName: "LVS"),
        ],
        allowExistingRun: true
    )

    do {
        _ = try await makeTestOrchestrator(projectRoot: root).run(
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

@Test func resumerRejectsAmbiguousPersistedStageResultReferences() async throws {
    let root = try makeTemporaryRoot("agent-resume-ambiguous-stage-result")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )

    let originalResultURL = root.appending(
        path: ".xcircuite/runs/run-1/stages/001-drc/result.json"
    )
    let duplicateResultPath = ".xcircuite/runs/run-1/stages/001-drc/duplicate-result.json"
    let duplicateResultURL = root.appending(path: duplicateResultPath)
    try Data(contentsOf: originalResultURL).write(to: duplicateResultURL, options: .atomic)
    let infrastructure = await TestFlowInfrastructure.bound(to: root)
    let duplicateReference = try await infrastructure.fileReference(
        forProjectRelativePath: duplicateResultPath,
        artifactID: "001-drc-result",
        role: .output,
        kind: .other,
        format: .json,
        inProjectAt: root,
        producerRunID: "run-1"
    )
    try await infrastructure.upsertRunArtifact(
        duplicateReference,
        runID: "run-1",
        inProjectAt: root
    )

    let qualification = try await TestToolQualificationFixtures.qualificationRecord(
        for: drcDescriptor(),
        projectRoot: root
    )
    let descriptor = qualification.descriptor
    do {
        _ = try await makeTestRunResumer(projectRoot: root).resumeRun(
            request: FlowRunResumeRequest(
                workspaceID: try testWorkspaceID(for: root),
                runID: "run-1"
            ),
            toolRegistry: try ToolRegistry(descriptors: [descriptor]),
            healthResults: [descriptor.toolID: qualification.health],
            executors: [
                SummaryStageExecutor(
                    stageID: "001-drc",
                    toolID: "native-drc",
                    status: .succeeded
                ),
            ]
        )
        Issue.record("Expected ambiguous stage-result references to be rejected")
    } catch let error as FlowExecutionError {
        #expect(error == .invalidRunArtifactReference(
            artifactID: "001-drc-result",
            reason: "expected exactly one output JSON stage-result artifact, found 2"
        ))
    } catch {
        throw error
    }
}

@Test func resumePreservesRunLevelArtifacts() async throws {
    let root = try makeTemporaryRoot("agent-resume-artifacts")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    try await TestFlowInfrastructure.bound(to: root).writeDesignDiff(
        DesignDiff(
            runID: "run-1",
            title: "DRC repair proposal",
            actor: "agent-1",
            changes: [
                DesignDiffChange(
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
    _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )

    let qualification = try await TestToolQualificationFixtures.qualificationRecord(
        for: drcDescriptor(),
        projectRoot: root
    )
    let descriptor = qualification.descriptor
    _ = try await makeTestRunResumer(projectRoot: root).resumeRun(
        request: FlowRunResumeRequest(workspaceID: try testWorkspaceID(for: root), runID: "run-1"),
        toolRegistry: try ToolRegistry(descriptors: [descriptor]),
        healthResults: [descriptor.toolID: qualification.health],
        executors: [
            SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
        ]
    )

    let manifest = try await TestFlowInfrastructure.bound(to: root).readJSON(
        FlowRunManifest.self,
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
    try await TestFlowInfrastructure.bound(to: root).createWorkspace(at: root)
    _ = try await TestFlowInfrastructure.bound(to: root).createRunDirectory(
        for: "run-1",
        inProjectAt: root
    )

    await #expect(throws: FlowRunResumeError.self) {
        try await makeTestRunResumer(projectRoot: root).resumeRun(
            request: FlowRunResumeRequest(workspaceID: try testWorkspaceID(for: root), runID: "run-1"),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: []
        )
    }
}

}

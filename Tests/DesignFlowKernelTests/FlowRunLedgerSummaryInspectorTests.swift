import DesignFlowKernel
import DesignFlowCLISupport
import Foundation
import Testing
import ToolQualification
import DesignFlowKernel

extension FlowRunLedgerSummaryTests {
@Test func inspectorSummarizesBlockedReviewRunForAgent() async throws {
    let root = try makeTemporaryRoot("agent-summary-review")
    defer { removeTemporaryRoot(root) }

    let descriptor = drcDescriptor()
    _ = try await DefaultFlowOrchestrator().run(
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
            ]
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
            SummaryStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
        ]
    )

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
    try XcircuiteWorkspaceStore().appendRunAction(
        XcircuiteRunActionRecord(
            actionID: "action-1",
            runID: "run-1",
            stageID: "001-drc",
            actor: XcircuiteRunActionActor(kind: .agent, identifier: "agent-1"),
            actionKind: "proposeDRCRepair",
            status: .blocked
        ),
        inProjectAt: root
    )

    let summary = try DefaultFlowRunLedgerInspector().inspectRun(
        runID: "run-1",
        projectRoot: root
    )

    #expect(summary.schemaVersion == 1)
    #expect(summary.runID == "run-1")
    #expect(summary.status == .blocked)
    #expect(summary.stages.map(\.stageID) == ["001-drc"])
    #expect(summary.stages.first?.status == .blocked)
    #expect(summary.stages.first?.gates.contains {
        $0.gateID == "approval" && $0.status == .incomplete
    } == true)
    #expect(summary.stages.first?.gates.contains {
        $0.gateID == "tool-trust" && $0.status == .passed
    } == true)
    #expect(summary.toolchain?.selectedToolIDs == ["native-drc"])
    #expect(summary.toolchain?.missingSelectionStageIDs == [])
    #expect(summary.designDiff?.reviewState == .proposed)
    #expect(summary.designDiff?.changeCount == 1)
    #expect(summary.designDiff?.domains == [.layout])
    #expect(summary.actionCount == 1)
    #expect(summary.approvalCount == 0)
    #expect(summary.diagnostics.contains { $0.code == "APPROVAL_PENDING" })
    #expect(summary.nextActions.map(\.kind).contains("reviewDesignDiff"))
    #expect(summary.nextActions.map(\.kind).contains("decideApproval"))
}

}

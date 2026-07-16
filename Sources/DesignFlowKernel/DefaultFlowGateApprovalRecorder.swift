import Foundation

public struct DefaultFlowGateApprovalRecorder: FlowGateApprovalRecording {
    private let loader: FlowRunLedgerLoading
    private let inspector: FlowRunLedgerInspecting
    private let ledgerCoordinator: FlowRunLedgerCoordinator

    public init(
        loader: FlowRunLedgerLoading,
        inspector: FlowRunLedgerInspecting,
        ledgerPersistence: any FlowRunLedgerPersisting
    ) {
        self.loader = loader
        self.inspector = inspector
        self.ledgerCoordinator = FlowRunLedgerCoordinator(persistence: ledgerPersistence)
    }

    public func recordApproval(_ request: FlowGateApprovalRequest) async throws -> FlowGateApprovalResult {
        if request.verdict == .waived,
           request.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FlowGateApprovalError.waiverReasonRequired
        }
        let ledger = try await loader.loadRunLedger(runID: request.runID)
        guard let stage = ledger.stages.first(where: { $0.stageID == request.stageID }) else {
            throw FlowGateApprovalError.stageNotFound(request.stageID)
        }
        guard stage.gates.contains(where: { $0.gateID == "approval" }) else {
            throw FlowGateApprovalError.approvalGateNotFound(request.stageID)
        }
        let planPath = "runs/\(request.runID)/plan.json"
        let resultPath = "runs/\(request.runID)/stages/\(request.stageID)/result.json"
        guard let planReference = ledger.artifacts.first(where: {
            $0.id.rawValue == "run-plan" || $0.locator.location.value == planPath
        }) else {
            throw FlowGateApprovalError.evidenceArtifactNotFound(planPath)
        }
        guard let resultReference = ledger.artifacts.first(where: {
            $0.id.rawValue == "\(request.stageID)-result"
                || $0.locator.location.value == resultPath
        }) else {
            throw FlowGateApprovalError.evidenceArtifactNotFound(resultPath)
        }

        let approval = FlowApprovalRecord(
            runID: request.runID,
            stageID: request.stageID,
            verdict: request.verdict.approvalRecordVerdict,
            reviewer: request.reviewer,
            reviewerKind: request.reviewerKind,
            note: request.note,
            createdAt: request.decidedAt,
            evidence: FlowApprovalEvidenceBinding(
                plan: planReference,
                stageResult: resultReference
            )
        )
        let persisted = try await ledgerCoordinator.update(
            runID: request.runID
        ) { ledger in
            ledger.approvals.removeAll { $0.stageID == request.stageID }
            ledger.approvals.append(approval)
            let decisionKind: FlowRunReviewDecisionKind = request.verdict == .waived
                ? .waiver
                : .approval
            ledger.actions.append(
                FlowRunActionRecord(
                    actionID: "approval-\(request.stageID)-\(ledger.runManifest.revision + 1)",
                    runID: request.runID,
                    stageID: request.stageID,
                    actor: FlowRunActor(kind: request.reviewerKind, identifier: request.reviewer),
                    actionKind: decisionKind.rawValue,
                    status: .succeeded,
                    inputs: [planReference, resultReference],
                    context: FlowRunActionContext(
                        reviewDecision: FlowRunActionContext.ReviewDecision(
                            kind: decisionKind,
                            decision: request.verdict.rawValue,
                            targetID: request.stageID,
                            targetPath: "runs/\(request.runID)/approvals/\(request.stageID).json",
                            reason: request.note
                        )
                    ),
                    createdAt: request.decidedAt
                )
            )
        }
        guard let persistedApproval = persisted.approvals.first(where: { $0.stageID == request.stageID }) else {
            throw FlowGateApprovalError.approvalRecordNotPersisted(runID: request.runID, stageID: request.stageID)
        }

        let summary = try await inspector.inspectRun(
            runID: request.runID,
            workspaceID: request.workspaceID
        )
        return FlowGateApprovalResult(approval: persistedApproval, summary: summary)
    }
}

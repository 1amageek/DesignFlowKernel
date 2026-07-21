import CircuiteFoundation
import Foundation

public struct DefaultFlowGateApprovalRecorder: FlowGateApprovalRecording {
    private let loader: FlowRunLedgerLoading
    private let inspector: FlowRunLedgerInspecting
    private let approvalPersistence: any FlowRunApprovalArtifactPersisting
    private let artifactLocationValidator: any FlowRunArtifactLocationValidator

    public init(
        loader: FlowRunLedgerLoading,
        inspector: FlowRunLedgerInspecting,
        approvalPersistence: any FlowRunApprovalArtifactPersisting,
        artifactLocationValidator: any FlowRunArtifactLocationValidator = DefaultFlowRunArtifactLocationValidator()
    ) {
        self.loader = loader
        self.inspector = inspector
        self.approvalPersistence = approvalPersistence
        self.artifactLocationValidator = artifactLocationValidator
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
        guard !ledger.approvals.contains(where: { $0.stageID == request.stageID }) else {
            throw FlowRunLedgerPersistenceError.duplicateApprovalID(
                runID: request.runID,
                approvalID: request.stageID
            )
        }
        let planPath = "runs/\(request.runID)/plan.json"
        let resultPath = "runs/\(request.runID)/stages/\(request.stageID)/result.json"
        let planCandidates = ledger.artifacts.filter { $0.id.rawValue == "run-plan" }
        let planReferences = planCandidates.filter {
            artifactLocationValidator.isReference(
                $0,
                boundTo: planPath,
                allowingContentAddressedVariant: false
            )
                && $0.locator.role == .input
                && $0.locator.kind == .other
                && $0.locator.format == .json
        }
        guard planCandidates.count == 1,
              planReferences.count == 1,
              let planReference = planReferences.first else {
            throw FlowGateApprovalError.evidenceArtifactNotFound(planPath)
        }
        let resultCandidates = ledger.artifacts.filter {
            $0.id.rawValue == "\(request.stageID)-result"
        }
        let resultReferences = resultCandidates.filter {
            artifactLocationValidator.isReference(
                $0,
                boundTo: resultPath,
                allowingContentAddressedVariant: false
            )
                && $0.locator.role == .output
                && $0.locator.kind == .other
                && $0.locator.format == .json
        }
        guard resultCandidates.count == 1,
              resultReferences.count == 1,
              let resultReference = resultReferences.first else {
            throw FlowGateApprovalError.evidenceArtifactNotFound(resultPath)
        }
        let reviewedResultContent = try await approvalPersistence.loadArtifactContent(
            for: resultReference
        )
        let reviewedResultDigest = try SHA256ContentDigester().digest(data: reviewedResultContent)
        let reviewedResultPath = "runs/\(request.runID)/review/approval-inputs/"
            + "\(request.stageID)-\(reviewedResultDigest.hexadecimalValue).json"
        let reviewedResultReference = ArtifactReference(
            id: try ArtifactID(
                rawValue: "approval-review-\(request.stageID.replacingOccurrences(of: ".", with: "-"))"
            ),
            locator: ArtifactLocator(
                location: try artifactLocationValidator.location(boundTo: reviewedResultPath),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: reviewedResultDigest,
            byteCount: UInt64(reviewedResultContent.count)
        )
        let retentionAction = FlowRunActionRecord(
            actionID: "approval-review-\(request.stageID)-\(reviewedResultDigest.hexadecimalValue)",
            runID: request.runID,
            stageID: request.stageID,
            actor: FlowRunActor(kind: .system, identifier: "design-flow-kernel"),
            actionKind: "approval.review.retain",
            status: .succeeded,
            inputs: [planReference],
            outputs: [reviewedResultReference],
            createdAt: ledger.runManifest.finishedAt ?? ledger.runManifest.createdAt
        )
        if let existingAction = ledger.actions.first(where: {
            $0.actionID == retentionAction.actionID
        }) {
            guard existingAction == retentionAction else {
                throw FlowRunLedgerPersistenceError.duplicateActionID(
                    runID: request.runID,
                    actionID: retentionAction.actionID
                )
            }
        } else {
            _ = try await approvalPersistence.appendActionArtifact(
                content: reviewedResultContent,
                reference: reviewedResultReference,
                action: retentionAction
            )
        }
        _ = try await approvalPersistence.loadArtifactContent(for: reviewedResultReference)

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
                stageResult: reviewedResultReference
            )
        )
        let approvalPath = "runs/\(request.runID)/approvals/\(request.stageID).json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let content = try encoder.encode(approval)
        let reference = ArtifactReference(
            id: try ArtifactID(rawValue: "approval-\(request.stageID)"),
            locator: ArtifactLocator(
                location: try artifactLocationValidator.location(boundTo: approvalPath),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: content),
            byteCount: UInt64(content.count)
        )
        let decisionKind: FlowRunReviewDecisionKind = request.verdict == .waived
            ? .waiver
            : .approval
        let action = FlowRunActionRecord(
            actionID: "approval-\(request.stageID)-\(reference.digest.hexadecimalValue)",
            runID: request.runID,
            stageID: request.stageID,
            actor: FlowRunActor(kind: request.reviewerKind, identifier: request.reviewer),
            actionKind: decisionKind.rawValue,
            status: .succeeded,
            inputs: [planReference, reviewedResultReference],
            outputs: [reference],
            context: FlowRunActionContext(
                reviewDecision: FlowRunActionContext.ReviewDecision(
                    kind: decisionKind,
                    decision: request.verdict.rawValue,
                    targetID: request.stageID,
                    targetPath: approvalPath,
                    reason: request.note
                )
            ),
            createdAt: request.decidedAt
        )
        let persisted = try await approvalPersistence.appendApprovalArtifact(
            content: content,
            reference: reference,
            approval: approval,
            action: action
        )
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

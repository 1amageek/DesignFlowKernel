import Foundation
import XcircuitePackage

public struct DefaultFlowGateApprovalRecorder: FlowGateApprovalRecording {
    private let packageStore: XcircuitePackageStore
    private let loader: FlowRunLedgerLoading
    private let inspector: FlowRunLedgerInspecting

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        loader: FlowRunLedgerLoading = FlowRunLedgerLoader(),
        inspector: FlowRunLedgerInspecting = DefaultFlowRunLedgerInspector()
    ) {
        self.packageStore = packageStore
        self.loader = loader
        self.inspector = inspector
    }

    public func recordApproval(_ request: FlowGateApprovalRequest) throws -> FlowGateApprovalResult {
        let ledger = try loader.loadRunLedger(runID: request.runID, projectRoot: request.projectRoot)
        guard let stage = ledger.stages.first(where: { $0.stageID == request.stageID }) else {
            throw FlowGateApprovalError.stageNotFound(request.stageID)
        }
        guard stage.gates.contains(where: { $0.gateID == "approval" }) else {
            throw FlowGateApprovalError.approvalGateNotFound(request.stageID)
        }

        let approval = XcircuiteApprovalRecord(
            runID: request.runID,
            stageID: request.stageID,
            verdict: request.verdict.approvalRecordVerdict,
            reviewer: request.reviewer,
            reviewerKind: request.reviewerKind,
            note: request.note,
            createdAt: request.decidedAt
        )
        try packageStore.recordApprovalAction(
            approval,
            metadata: [
                "source": .string("design-flow.approve-gate"),
                "gateID": .string("approval"),
            ],
            inProjectAt: request.projectRoot
        )
        guard let persistedApproval = try packageStore.loadApproval(
            runID: request.runID,
            stageID: request.stageID,
            inProjectAt: request.projectRoot
        ) else {
            throw FlowGateApprovalError.approvalRecordNotPersisted(
                runID: request.runID,
                stageID: request.stageID
            )
        }

        let summary = try inspector.inspectRun(
            runID: request.runID,
            projectRoot: request.projectRoot
        )
        return FlowGateApprovalResult(approval: persistedApproval, summary: summary)
    }
}

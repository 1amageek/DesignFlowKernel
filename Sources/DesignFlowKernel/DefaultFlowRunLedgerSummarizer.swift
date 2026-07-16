import Foundation
import ToolQualification

public struct DefaultFlowRunLedgerSummarizer: FlowRunLedgerSummarizing {
    private let identifierPolicy = FlowRunReviewIdentifierPolicy()

    public init() {}

    public func summarize(_ ledger: FlowRunLedger) -> FlowRunLedgerSummary {
        FlowRunLedgerSummary(
            runID: ledger.runID,
            status: ledger.runManifest.status,
            stages: ledger.stages.map(stageSummary),
            toolchain: toolchainSummary(from: ledger.toolchain),
            designDiff: designDiffSummary(from: ledger.designDiff),
            progressEventCount: ledger.progressEvents.count,
            latestProgressEvent: ledger.progressEvents.last,
            cancellationRequest: ledger.cancellationRequest,
            actionCount: ledger.actions.count,
            approvalCount: ledger.approvals.count,
            diagnostics: ledger.stages.flatMap { $0.diagnostics + $0.gates.flatMap(\.diagnostics) },
            nextActions: nextActions(from: ledger),
            suggestedCommandSelections: ledger.suggestedCommandSelections
        )
    }

    private func stageSummary(_ stage: FlowStageResult) -> FlowRunStageSummary {
        FlowRunStageSummary(
            stageID: stage.stageID,
            status: stage.status,
            gates: stage.gates.map {
                FlowRunGateSummary(
                    gateID: $0.gateID,
                    status: $0.status,
                    diagnosticCodes: $0.diagnostics.map(\.code)
                )
            },
            diagnosticCodes: stage.diagnostics.map(\.code),
            artifactCount: stage.artifacts.count,
            attemptCount: stage.attempts.count,
            retryCount: max(0, stage.attempts.count - 1)
        )
    }

    private func toolchainSummary(from manifest: FlowToolchainManifest?) -> FlowRunToolchainSummary? {
        guard let manifest else {
            return nil
        }
        return FlowRunToolchainSummary(
            stageCount: manifest.stages.count,
            selectedToolIDs: Set(manifest.stages.compactMap(\.selectedToolID)).sorted(),
            rejectedEvaluationCount: manifest.stages.reduce(0) { count, stage in
                count + stage.evaluations.filter { $0.decision.status == .rejected }.count
            },
            missingSelectionStageIDs: manifest.stages
                .filter { $0.requiredTool != nil && $0.selectedToolID == nil }
                .map(\.stageID)
                .sorted(),
            profileID: manifest.profile?.profileID,
            pdkID: manifest.profile?.pdkID,
            technologyCatalogID: manifest.profile?.technologyCatalogID,
            technologyCatalogPath: manifest.profile?.technologyCatalogPath,
            profileArtifactPath: manifest.profile?.profileArtifactPath
        )
    }

    private func designDiffSummary(from diff: DesignDiff?) -> FlowRunDesignDiffSummary? {
        guard let diff else {
            return nil
        }
        return FlowRunDesignDiffSummary(
            title: diff.title,
            actor: diff.actor,
            reviewState: diff.reviewState,
            changeCount: diff.changes.count,
            domains: Array(Set(diff.changes.map(\.domain))).sorted { $0.rawValue < $1.rawValue }
        )
    }

    private func nextActions(from ledger: FlowRunLedger) -> [FlowRunNextAction] {
        var actions: [FlowRunNextAction] = []
        let decidedStageIDs = Set(ledger.approvals.map(\.stageID))

        if let diff = ledger.designDiff, diff.reviewState == .proposed {
            actions.append(
                FlowRunNextAction(
                    actionID: "review-design-diff",
                    kind: "reviewDesignDiff",
                    severity: .warning,
                    reason: "A proposed design diff is waiting for review.",
                    diagnosticCodes: []
                )
            )
        }
        if let cancellation = ledger.cancellationRequest {
            actions.append(
                FlowRunNextAction(
                    actionID: "review-cancellation-request",
                    kind: "reviewCancellation",
                    severity: ledger.runManifest.status == .cancelled ? .info : .warning,
                    reason: "A run cancellation request is recorded by \(cancellation.requestedBy): \(cancellation.reason)",
                    diagnosticCodes: []
                )
            )
        }
        for stage in ledger.stages {
            actions.append(contentsOf: nextActions(for: stage, decidedStageIDs: decidedStageIDs))
        }
        if actions.isEmpty, ledger.runManifest.status == .succeeded {
            actions.append(
                FlowRunNextAction(
                    actionID: "archive-or-continue",
                    kind: "archiveOrContinue",
                    severity: .info,
                    reason: "The run succeeded; archive the artifacts or start the next design iteration.",
                    diagnosticCodes: []
                )
            )
        }
        return actions
    }

    private func nextActions(
        for stage: FlowStageResult,
        decidedStageIDs: Set<String>
    ) -> [FlowRunNextAction] {
        var actions: [FlowRunNextAction] = []
        for gate in stage.gates where gate.status == .incomplete && gate.gateID == "approval" {
            let decided = decidedStageIDs.contains(stage.stageID)
            actions.append(
                FlowRunNextAction(
                    actionID: stageScopedID(stage.stageID, decided ? "resume-run" : "decide-approval"),
                    kind: decided ? "resumeRun" : "decideApproval",
                    stageID: stage.stageID,
                    severity: decided ? .info : .warning,
                    reason: decided
                        ? "A review decision is recorded; resume the run to apply the approval gate."
                        : "The stage is waiting for a review decision.",
                    diagnosticCodes: gate.diagnostics.map(\.code)
                )
            )
        }
        if stage.gates.contains(where: { $0.gateID == "tool-trust" && $0.status == .failed }) {
            actions.append(nextAction(
                stage: stage,
                suffix: "repair-toolchain",
                kind: "repairToolchain",
                severity: .error,
                reason: "The selected tool did not satisfy the trust gate."
            ))
        }
        if stage.attempts.count > 1 {
            actions.append(nextAction(
                stage: stage,
                suffix: "review-retry-attempts",
                kind: "reviewRetryAttempts",
                severity: stage.status == .failed ? .warning : .info,
                reason: "The stage has retry attempts that require review."
            ))
        }
        for gate in stage.gates where gate.gateID.hasSuffix("-artifacts") && gate.status != .passed {
            actions.append(
                FlowRunNextAction(
                    actionID: stageScopedID(stage.stageID, "repair-\(gate.gateID)"),
                    kind: "repairArtifactCoverage",
                    stageID: stage.stageID,
                    severity: gate.status == .failed || gate.status == .blocked ? .error : .warning,
                    reason: "The \(gate.gateID) gate reported inconsistent artifact coverage.",
                    diagnosticCodes: gate.diagnostics.map(\.code)
                )
            )
        }
        if stage.status == .failed {
            actions.append(nextAction(
                stage: stage,
                suffix: "inspect-failure",
                kind: "inspectFailure",
                severity: .error,
                reason: "The stage failed and needs diagnostic review before retry."
            ))
        } else if stage.status == .blocked, !actions.contains(where: { $0.stageID == stage.stageID }) {
            actions.append(nextAction(
                stage: stage,
                suffix: "resolve-blocker",
                kind: "resolveBlocker",
                severity: .warning,
                reason: "The stage is blocked and needs an unblock action."
            ))
        }
        return actions
    }

    private func nextAction(
        stage: FlowStageResult,
        suffix: String,
        kind: String,
        severity: FlowDiagnosticSeverity,
        reason: String
    ) -> FlowRunNextAction {
        FlowRunNextAction(
            actionID: stageScopedID(stage.stageID, suffix),
            kind: kind,
            stageID: stage.stageID,
            severity: severity,
            reason: reason,
            diagnosticCodes: stage.diagnostics.map(\.code) + stage.gates.flatMap { $0.diagnostics.map(\.code) }
        )
    }

    private func stageScopedID(_ stageID: String, _ suffix: String) -> String {
        identifierPolicy.safeStageScopedID(stageID: stageID, suffix: suffix)
    }
}

import CircuiteFoundation
import Foundation

public struct DefaultFlowRunGuardEvaluator: Sendable {
    private let snapshotBuilder: DefaultFlowRunLoopSnapshotBuilder
    private let storage: XcircuiteWorkspaceStore

    public init(
        snapshotBuilder: DefaultFlowRunLoopSnapshotBuilder = DefaultFlowRunLoopSnapshotBuilder(),
        storage: XcircuiteWorkspaceStore = XcircuiteWorkspaceStore()
    ) {
        self.snapshotBuilder = snapshotBuilder
        self.storage = storage
    }

    public func evaluateRunGuard(
        runID: String,
        projectRoot: URL,
        profile: XcircuiteAgentLoopProfile = .makeDefault(),
        generatedAt: Date = Date(),
        persist: Bool = true
    ) throws -> FlowRunGuardEvaluationResult {
        let summary = try snapshotBuilder.summarizeLoop(
            runID: runID,
            projectRoot: projectRoot,
            profile: profile,
            generatedAt: generatedAt,
            persist: persist
        )
        let foundationArtifactReferences = summary.artifactReferences
        let verdict = buildVerdict(
            runID: runID,
            projectRoot: projectRoot,
            profile: profile,
            snapshot: summary.snapshot,
            iterations: summary.iterations,
            generatedAt: generatedAt,
            artifactReferences: foundationArtifactReferences
        )
        var artifactReferences = foundationArtifactReferences
        if persist {
            let verdictArtifact = try storage.writeRunGuardVerdict(
                verdict,
                inProjectAt: projectRoot
            )
            artifactReferences.append(try verdictArtifact.foundationArtifactReference(role: .output))
        }
        return FlowRunGuardEvaluationResult(
            runID: runID,
            profileID: profile.profileID,
            snapshot: summary.snapshot,
            verdict: verdict,
            artifactReferences: artifactReferences
        )
    }

    private func buildVerdict(
        runID: String,
        projectRoot: URL,
        profile: XcircuiteAgentLoopProfile,
        snapshot: XcircuiteAgentLoopSnapshot,
        iterations: [XcircuiteLoopIterationSummary],
        generatedAt: Date,
        artifactReferences: [ArtifactReference]
    ) -> XcircuiteRunGuardVerdict {
        var detectors: [XcircuiteRunGuardVerdict.DetectorResult] = []
        var requiredActions: [XcircuiteRunGuardVerdict.RequiredAction] = []

        if detectorEnabled("budgetExceeded", profile: profile),
           !snapshot.budgetUsage.exceededBudgetIDs.isEmpty {
            detectors.append(
                detector(
                    "budgetExceeded",
                    severity: .warning,
                    reason: "loop budget exceeded: \(snapshot.budgetUsage.exceededBudgetIDs.joined(separator: ", "))"
                )
            )
            requiredActions.append(
                requiredAction(
                    "reduce-scope",
                    kind: "reduceScope",
                    severity: .warning,
                    reason: "Reduce loop scope or request a larger budget."
                )
            )
        }

        if detectorEnabled("missingRequiredEvidence", profile: profile),
           snapshot.evidenceCoverage.missingCount > 0 {
            let missing = snapshot.evidenceCoverage.items.filter { $0.status == .missing }
            detectors.append(
                detector(
                    "missingRequiredEvidence",
                    severity: .warning,
                    reason: "required evidence is missing",
                    artifactIDs: missing.compactMap(\.artifactID)
                )
            )
            requiredActions.append(
                requiredAction(
                    "produce-required-evidence",
                    kind: "produceEvidence",
                    severity: .warning,
                    reason: "Run or attach the missing required evidence before continuing."
                )
            )
        }

        if detectorEnabled("staleEvidence", profile: profile),
           snapshot.evidenceCoverage.staleCount > 0 {
            let stale = snapshot.evidenceCoverage.items.filter { $0.status == .stale }
            detectors.append(
                detector(
                    "staleEvidence",
                    severity: .warning,
                    reason: "required evidence is stale",
                    artifactIDs: stale.flatMap { item in item.artifactReferences.compactMap(\.artifactID) }
                )
            )
            requiredActions.append(
                requiredAction(
                    "rerun-stale-evidence",
                    kind: "rerunVerification",
                    severity: .warning,
                    reason: "Refresh stale verification evidence."
                )
            )
        }

        if detectorEnabled("approvalRequired", profile: profile),
           snapshot.approvalState.status == .pending || snapshot.approvalState.status == .rejected {
            let severity: XcircuiteRunGuardSeverity = snapshot.approvalState.status == .rejected ? .error : .warning
            detectors.append(
                detector(
                    "approvalRequired",
                    severity: severity,
                    reason: "human approval is \(snapshot.approvalState.status.rawValue)",
                    diagnosticCodes: snapshot.approvalState.pendingStageIDs + snapshot.approvalState.rejectedStageIDs
                )
            )
            requiredActions.append(
                requiredAction(
                    "request-human-approval",
                    kind: "requestHumanApproval",
                    severity: severity,
                    reason: "Resolve pending or rejected approval before continuing.",
                    stageIDs: snapshot.approvalState.pendingStageIDs + snapshot.approvalState.rejectedStageIDs
                )
            )
        }

        if detectorEnabled("toolFailureBurst", profile: profile) {
            let threshold = Int(detectorThreshold("toolFailureBurst", profile: profile) ?? 3)
            if snapshot.diagnosticTrend.failedDiagnosticCount >= threshold {
                detectors.append(
                    detector(
                        "toolFailureBurst",
                        severity: .warning,
                        reason: "failed diagnostics reached \(snapshot.diagnosticTrend.failedDiagnosticCount)",
                        diagnosticCodes: Array(snapshot.diagnosticTrend.repeatedCodes.keys).sorted()
                    )
                )
                requiredActions.append(
                    requiredAction(
                        "inspect-tool-failures",
                        kind: "inspectDiagnostics",
                        severity: .warning,
                        reason: "Inspect repeated tool failures before continuing."
                    )
                )
            }
        }

        if detectorEnabled("repeatedAction", profile: profile) {
            let threshold = Int(detectorThreshold("repeatedAction", profile: profile) ?? 3)
            let repeated = repeatedActionKinds(iterations: iterations, threshold: threshold)
            if !repeated.isEmpty {
                detectors.append(
                    detector(
                        "repeatedAction",
                        severity: .warning,
                        reason: "same action kind repeated without enough new evidence",
                        diagnosticCodes: repeated
                    )
                )
            }
        }

        if detectorEnabled("noProgress", profile: profile) {
            let threshold = Int(detectorThreshold("noProgress", profile: profile) ?? 5)
            if snapshot.actionCount >= threshold
                && snapshot.metricTrend.acceptedCount == 0
                && (snapshot.metricTrend.rejectedCount + snapshot.metricTrend.needsHumanReviewCount + snapshot.metricTrend.blockedCount) > 0 {
                detectors.append(
                    detector(
                        "noProgress",
                        severity: .warning,
                        reason: "loop has actions and failing evaluation signals but no accepted evaluation"
                    )
                )
            }
        }

        if detectorEnabled("worseningTrend", profile: profile),
           snapshot.metricTrend.rejectedCount > 0 || snapshot.metricTrend.blockedCount > 0 {
            detectors.append(
                detector(
                    "worseningTrend",
                    severity: .warning,
                    reason: "rejected or blocked evaluation results are present",
                    diagnosticCodes: snapshot.metricTrend.channelIDs
                )
            )
        }

        if detectorEnabled("verificationBypass", profile: profile),
           snapshot.budgetUsage.designChangeCount > 0,
           snapshot.evidenceCoverage.availableArtifactIDs.isEmpty {
            detectors.append(
                detector(
                    "verificationBypass",
                    severity: .error,
                    reason: "design changed but no verification evidence is available"
                )
            )
            requiredActions.append(
                requiredAction(
                    "run-verification-after-change",
                    kind: "runVerification",
                    severity: .error,
                    reason: "Generate verification evidence for the design changes."
                )
            )
        }

        if detectorEnabled("changeMagnitudeExceeded", profile: profile),
           snapshot.budgetUsage.exceededBudgetIDs.contains("maxDesignChanges")
            || snapshot.budgetUsage.exceededBudgetIDs.contains("maxChangedFiles") {
            detectors.append(
                detector(
                    "changeMagnitudeExceeded",
                    severity: .warning,
                    reason: "design change magnitude exceeded profile budget"
                )
            )
        }

        let status = verdictStatus(snapshot: snapshot, detectors: detectors)
        let suggestedCommands = suggestedCommands(
            projectRoot: projectRoot,
            runID: runID,
            profile: profile,
            status: status
        )
        return XcircuiteRunGuardVerdict(
            verdictID: "guard-\(runID)",
            runID: runID,
            profileID: profile.profileID,
            snapshotID: snapshot.snapshotID,
            status: status,
            generatedAt: generatedAt,
            triggeredDetectors: detectors,
            requiredActions: stableUniqueRequiredActions(requiredActions),
            suggestedCommands: suggestedCommands,
            artifactReferences: artifactReferences,
            metadata: [
                "detectorCount": .number(Double(detectors.count)),
            ]
        )
    }

    private func verdictStatus(
        snapshot: XcircuiteAgentLoopSnapshot,
        detectors: [XcircuiteRunGuardVerdict.DetectorResult]
    ) -> XcircuiteRunGuardVerdict.Status {
        if snapshot.resumeReadiness.reasons.contains("run is cancelled") {
            return .cancelled
        }
        if detectors.contains(where: { $0.severity >= .error }) {
            return .blocked
        }
        if !detectors.isEmpty || snapshot.resumeReadiness.status == .needsHumanReview {
            return .needsHumanReview
        }
        return .continue
    }

    private func suggestedCommands(
        projectRoot: URL,
        runID: String,
        profile: XcircuiteAgentLoopProfile,
        status: XcircuiteRunGuardVerdict.Status
    ) -> [XcircuiteRunGuardVerdict.SuggestedCommand] {
        let projectPath = projectRoot.path(percentEncoded: false)
        var commands = [
            XcircuiteRunGuardVerdict.SuggestedCommand(
                commandID: "design-flow.summarize-loop",
                executable: "design-flow",
                arguments: [
                    "summarize-loop",
                    "--project-root",
                    projectPath,
                    "--run-id",
                    runID,
                ],
                reason: "refresh loop snapshot"
            ),
            XcircuiteRunGuardVerdict.SuggestedCommand(
                commandID: "design-flow.inspect-run",
                executable: "design-flow",
                arguments: [
                    "inspect-run",
                    "--project-root",
                    projectPath,
                    "--run-id",
                    runID,
                ],
                reason: "inspect run ledger"
            ),
        ]
        if status != .continue {
            commands.append(
                XcircuiteRunGuardVerdict.SuggestedCommand(
                    commandID: "design-flow.review-run",
                    executable: "design-flow",
                    arguments: [
                        "review-run",
                        "--project-root",
                        projectPath,
                        "--run-id",
                        runID,
                    ],
                    reason: "open human or Agent review bundle"
                )
            )
        }
        if !profile.requiredEvidence.isEmpty {
            commands.append(
                XcircuiteRunGuardVerdict.SuggestedCommand(
                    commandID: "design-flow.evaluate-run-guard",
                    executable: "design-flow",
                    arguments: [
                        "evaluate-run-guard",
                        "--project-root",
                        projectPath,
                        "--run-id",
                        runID,
                    ],
                    reason: "recompute guard verdict after evidence changes"
                )
            )
        }
        return commands
    }

    private func detector(
        _ detectorID: String,
        severity: XcircuiteRunGuardSeverity,
        reason: String,
        actionIDs: [String] = [],
        artifactIDs: [String] = [],
        diagnosticCodes: [String] = []
    ) -> XcircuiteRunGuardVerdict.DetectorResult {
        XcircuiteRunGuardVerdict.DetectorResult(
            detectorID: detectorID,
            severity: severity,
            reason: reason,
            actionIDs: actionIDs,
            artifactIDs: stableUnique(artifactIDs),
            diagnosticCodes: stableUnique(diagnosticCodes)
        )
    }

    private func requiredAction(
        _ actionID: String,
        kind: String,
        severity: XcircuiteRunGuardSeverity,
        reason: String,
        artifactIDs: [String] = [],
        stageIDs: [String] = []
    ) -> XcircuiteRunGuardVerdict.RequiredAction {
        XcircuiteRunGuardVerdict.RequiredAction(
            actionID: actionID,
            kind: kind,
            severity: severity,
            reason: reason,
            artifactIDs: stableUnique(artifactIDs),
            stageIDs: stableUnique(stageIDs)
        )
    }

    private func detectorEnabled(_ detectorID: String, profile: XcircuiteAgentLoopProfile) -> Bool {
        profile.detectors.first { $0.detectorID == detectorID }?.enabled ?? true
    }

    private func detectorThreshold(_ detectorID: String, profile: XcircuiteAgentLoopProfile) -> Double? {
        profile.detectors.first { $0.detectorID == detectorID }?.threshold
    }

    private func repeatedActionKinds(
        iterations: [XcircuiteLoopIterationSummary],
        threshold: Int
    ) -> [String] {
        let kinds = iterations.flatMap(\.actionKinds)
        return Dictionary(grouping: kinds, by: { $0 })
            .mapValues(\.count)
            .filter { $0.value >= threshold }
            .map(\.key)
            .sorted()
    }

    private func stableUniqueRequiredActions(
        _ actions: [XcircuiteRunGuardVerdict.RequiredAction]
    ) -> [XcircuiteRunGuardVerdict.RequiredAction] {
        var seen: Set<String> = []
        var result: [XcircuiteRunGuardVerdict.RequiredAction] = []
        for action in actions where !seen.contains(action.actionID) {
            seen.insert(action.actionID)
            result.append(action)
        }
        return result
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

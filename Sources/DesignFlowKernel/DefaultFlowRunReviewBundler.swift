import Foundation

private struct RetainedHistoryReviewSignal {
    var artifactPaths: Set<String> = []
    var diagnosticCodes: Set<String> = []
    var needsReview = false
    var needsRepair = false
}

public struct DefaultFlowRunReviewBundler: FlowRunReviewBundling {
    private let loader: any FlowRunLedgerLoading
    private let summarizer: any FlowRunLedgerSummarizing
    private let identifierPolicy = FlowRunReviewIdentifierPolicy()

    public init(
        loader: any FlowRunLedgerLoading = FlowRunLedgerLoader(),
        summarizer: any FlowRunLedgerSummarizing = DefaultFlowRunLedgerSummarizer()
    ) {
        self.loader = loader
        self.summarizer = summarizer
    }

    public func makeReviewBundle(runID: String, projectRoot: URL) throws -> FlowRunReviewBundle {
        let ledger = try loader.loadRunLedger(runID: runID, projectRoot: projectRoot)
        let summary = summarizer.summarize(ledger)
        let agentLoopSnapshot = try loadOptionalRunJSON(
            XcircuiteAgentLoopSnapshot.self,
            runID: ledger.runID,
            relativePath: "loop/snapshot.json",
            projectRoot: projectRoot
        )
        let runGuardVerdict = try loadOptionalRunJSON(
            XcircuiteRunGuardVerdict.self,
            runID: ledger.runID,
            relativePath: "loop/guard-verdict.json",
            projectRoot: projectRoot
        )
        let crossArtifactEvaluation = try loadOptionalRunJSON(
            XcircuiteCrossArtifactEvaluation.self,
            runID: ledger.runID,
            relativePath: "reports/cross-artifact-evaluation.json",
            projectRoot: projectRoot
        )
        let artifacts = try reviewArtifacts(from: ledger, projectRoot: projectRoot)
        let items = reviewItems(
            from: ledger,
            summary: summary,
            artifacts: artifacts,
            projectRoot: projectRoot,
            agentLoopSnapshot: agentLoopSnapshot,
            runGuardVerdict: runGuardVerdict,
            crossArtifactEvaluation: crossArtifactEvaluation
        )
        let decisionActions = try reviewDecisionActions(from: ledger.actions)
        return FlowRunReviewBundle(
            runID: ledger.runID,
            status: summary.status,
            runDirectoryPath: ledger.runDirectory.path(percentEncoded: false),
            summary: summary,
            reviewItems: items,
            artifacts: artifacts,
            approvals: ledger.approvals,
            decisionActions: decisionActions,
            coverageRefs: coverageRefs(
                from: artifacts,
                reviewItems: items,
                approvals: ledger.approvals,
                decisionActions: decisionActions
            ),
            agentLoopSnapshot: agentLoopSnapshot,
            runGuardVerdict: runGuardVerdict,
            crossArtifactEvaluation: crossArtifactEvaluation
        )
    }

    private func reviewArtifacts(
        from ledger: FlowRunLedger,
        projectRoot: URL
    ) throws -> [FlowRunReviewArtifact] {
        let recordedReferencesByPath = try recordedReferencesByPath(from: ledger, projectRoot: projectRoot)
        var artifacts: [FlowRunReviewArtifact] = [
            runArtifact(
                role: "run-manifest",
                runID: ledger.runID,
                relativePath: "manifest.json",
                projectRoot: projectRoot,
                recordedReferencesByPath: recordedReferencesByPath
            ),
        ]
        if ledger.plan != nil {
            artifacts.append(runArtifact(role: "plan", runID: ledger.runID, relativePath: "plan.json", projectRoot: projectRoot, recordedReferencesByPath: recordedReferencesByPath))
        }
        if ledger.toolchain != nil {
            artifacts.append(runArtifact(role: "toolchain", runID: ledger.runID, relativePath: "toolchain.json", projectRoot: projectRoot, recordedReferencesByPath: recordedReferencesByPath))
        }
        if !ledger.progressEvents.isEmpty {
            artifacts.append(
                runArtifact(
                    role: "run-progress",
                    runID: ledger.runID,
                    relativePath: FlowRunProgressStore.progressRelativePath,
                    projectRoot: projectRoot,
                    recordedReferencesByPath: recordedReferencesByPath,
                    format: .text
                )
            )
        }
        if ledger.cancellationRequest != nil {
            artifacts.append(
                runArtifact(
                    role: "run-cancellation-request",
                    runID: ledger.runID,
                    relativePath: FlowRunProgressStore.cancellationRelativePath,
                    projectRoot: projectRoot,
                    recordedReferencesByPath: recordedReferencesByPath
                )
            )
        }
        if ledger.designDiff != nil {
            artifacts.append(
                runArtifact(
                    role: "design-diff",
                    runID: ledger.runID,
                    relativePath: "design-diff.json",
                    projectRoot: projectRoot,
                    recordedReferencesByPath: recordedReferencesByPath,
                    kind: .designDiff
                )
            )
        }
        if !ledger.actions.isEmpty {
            artifacts.append(
                runArtifact(
                    role: "action-ledger",
                    runID: ledger.runID,
                    relativePath: "actions.jsonl",
                    projectRoot: projectRoot,
                    recordedReferencesByPath: recordedReferencesByPath,
                    format: .text
                )
            )
        }
        appendOptionalRunArtifact(
            role: "agent-loop-snapshot",
            runID: ledger.runID,
            relativePath: "loop/snapshot.json",
            projectRoot: projectRoot,
            recordedReferencesByPath: recordedReferencesByPath,
            into: &artifacts
        )
        appendOptionalRunArtifact(
            role: "run-guard-verdict",
            runID: ledger.runID,
            relativePath: "loop/guard-verdict.json",
            projectRoot: projectRoot,
            recordedReferencesByPath: recordedReferencesByPath,
            into: &artifacts
        )
        appendOptionalRunArtifact(
            role: "cross-artifact-evaluation",
            runID: ledger.runID,
            relativePath: "reports/cross-artifact-evaluation.json",
            projectRoot: projectRoot,
            recordedReferencesByPath: recordedReferencesByPath,
            into: &artifacts
        )
        for approval in ledger.approvals {
            artifacts.append(
                runArtifact(
                    role: "approval",
                    runID: ledger.runID,
                    relativePath: "approvals/\(approval.stageID).json",
                    projectRoot: projectRoot,
                    recordedReferencesByPath: recordedReferencesByPath,
                    stageID: approval.stageID
                )
            )
        }
        for stage in ledger.stages {
            artifacts.append(
                runArtifact(
                    role: "stage-result",
                    runID: ledger.runID,
                    relativePath: "stages/\(stage.stageID)/result.json",
                    projectRoot: projectRoot,
                    recordedReferencesByPath: recordedReferencesByPath,
                    stageID: stage.stageID
                )
            )
            artifacts.append(
                contentsOf: try stage.artifacts.map { reference in
                    let legacyReference = try reference.legacyXcircuiteReference()
                    return FlowRunReviewArtifact(
                        role: reviewRole(for: legacyReference),
                        artifactID: legacyReference.artifactID,
                        stageID: stage.stageID,
                        path: legacyReference.path,
                        kind: legacyReference.kind,
                        format: legacyReference.format,
                        sha256: legacyReference.sha256,
                        byteCount: legacyReference.byteCount,
                        integrity: artifactIntegrity(
                            for: legacyReference,
                            stageID: stage.stageID,
                            projectRoot: projectRoot
                        )
                    )
                }
            )
        }
        appendRunManifestArtifacts(
            from: ledger,
            projectRoot: projectRoot,
            into: &artifacts
        )
        return artifacts
    }

    private func reviewRole(for reference: XcircuiteFileReference) -> String {
        guard let artifactID = reference.artifactID else {
            return "stage-artifact"
        }
        if artifactID == "agent-loop-snapshot" {
            return "agent-loop-snapshot"
        }
        if artifactID == "run-guard-verdict" {
            return "run-guard-verdict"
        }
        if artifactID == "cross-artifact-evaluation" {
            return "cross-artifact-evaluation"
        }
        if let role = retainedHistoryReviewRole(for: reference) {
            return role
        }
        if artifactID.hasSuffix("-summary") {
            return "stage-summary"
        }
        if artifactID.hasSuffix("-attempts") {
            return "stage-attempts"
        }
        if artifactID == "post-layout-comparison" {
            return "post-layout-comparison"
        }
        return "stage-artifact"
    }

    private func recordedReferencesByPath(
        from ledger: FlowRunLedger,
        projectRoot: URL
    ) throws -> [String: XcircuiteFileReference] {
        var references: [String: XcircuiteFileReference] = [:]
        for reference in ledger.runManifest.artifacts {
            references[reference.path] = reference
        }
        let projectManifest = try XcircuitePackageStore().loadManifest(forProjectAt: projectRoot)
        for reference in projectManifest.files {
            references[reference.path] = reference
        }
        return references
    }

    private func reviewDecisionActions(
        from actions: [XcircuiteRunActionRecord]
    ) throws -> [XcircuiteRunReviewDecisionAction] {
        var decisions: [XcircuiteRunReviewDecisionAction] = []
        for action in actions {
            if let decision = try XcircuiteRunReviewDecisionAction(record: action) {
                decisions.append(decision)
            }
        }
        return decisions.sorted { left, right in
            if left.decidedAt != right.decidedAt {
                return left.decidedAt < right.decidedAt
            }
            return left.actionRecordID < right.actionRecordID
        }
    }

    private func coverageRefs(
        from artifacts: [FlowRunReviewArtifact],
        reviewItems: [FlowRunReviewItem],
        approvals: [XcircuiteApprovalRecord],
        decisionActions: [XcircuiteRunReviewDecisionAction]
    ) -> [FlowRunReviewBundle.CoverageRef] {
        let reviewItemsByArtifactPath = reviewItemIDsByArtifactPath(reviewItems)
        var refs: [FlowRunReviewBundle.CoverageRef] = artifacts.map { artifact in
            FlowRunReviewBundle.CoverageRef(
                domain: coverageDomain(for: artifact),
                role: artifact.role,
                stageID: artifact.stageID,
                artifactID: artifact.artifactID,
                path: artifact.path,
                integrityStatus: artifact.integrity?.status,
                reviewItemIDs: reviewItemsByArtifactPath[artifact.path, default: []]
            )
        }
        refs.append(contentsOf: artifacts.compactMap { artifact in
            guard artifact.integrity != nil else {
                return nil
            }
            return FlowRunReviewBundle.CoverageRef(
                domain: "integrity",
                role: artifact.role,
                stageID: artifact.stageID,
                artifactID: artifact.artifactID,
                path: artifact.path,
                integrityStatus: artifact.integrity?.status,
                reviewItemIDs: reviewItemsByArtifactPath[artifact.path, default: []]
            )
        })
        refs.append(contentsOf: approvals.map { approval in
            FlowRunReviewBundle.CoverageRef(
                domain: "approval",
                role: "approval-record",
                stageID: approval.stageID,
                path: identifierPolicy.approvalArtifactPath(runID: approval.runID, stageID: approval.stageID)
            )
        })
        refs.append(contentsOf: decisionActions.map { decision in
            FlowRunReviewBundle.CoverageRef(
                domain: coverageDomain(for: decision.decisionKind),
                role: decision.decisionKind.rawValue,
                stageID: decision.stageID,
                path: decision.targetPath,
                decisionActionIDs: [decision.actionRecordID]
            )
        })
        return refs.sorted { left, right in
            if left.domain != right.domain {
                return left.domain < right.domain
            }
            if (left.stageID ?? "") != (right.stageID ?? "") {
                return (left.stageID ?? "") < (right.stageID ?? "")
            }
            return (left.path ?? left.role) < (right.path ?? right.role)
        }
    }

    private func reviewItemIDsByArtifactPath(
        _ reviewItems: [FlowRunReviewItem]
    ) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for item in reviewItems {
            for path in item.artifactPaths {
                result[path, default: []].append(item.itemID)
            }
        }
        return result.mapValues { $0.sorted() }
    }

    private func coverageDomain(for artifact: FlowRunReviewArtifact) -> String {
        if artifact.role == "design-diff" || artifact.kind == .designDiff {
            return "diff"
        }
        if artifact.kind == .waveform || artifact.path.contains("/waveform") {
            return "waveform"
        }
        if artifact.role.hasPrefix("planning-") || artifact.path.contains("/planning/") {
            return "planning"
        }
        if artifact.role == "approval" || artifact.path.contains("/approvals/") {
            return "approval"
        }
        let searchable = [
            artifact.role,
            artifact.artifactID ?? "",
            artifact.stageID ?? "",
            artifact.path,
            artifact.kind.rawValue,
            artifact.format.rawValue,
        ]
        .joined(separator: " ")
        .lowercased()
        if searchable.contains("drc") {
            return "drc"
        }
        if searchable.contains("lvs") {
            return "lvs"
        }
        if searchable.contains("pex") || searchable.contains("spef") || searchable.contains("post-layout") {
            return "pex"
        }
        if searchable.contains("release-envelope") {
            return "release-gate"
        }
        if searchable.contains("retained")
            || searchable.contains("retention-index")
            || searchable.contains("history-dashboard")
            || searchable.contains("history.jsonl")
            || searchable.contains("workflow-run")
            || searchable.contains("workflow-report") {
            return "retained-history"
        }
        if searchable.contains("review") {
            return "review"
        }
        if searchable.contains("agent-loop") || searchable.contains("run-guard") {
            return "agent-loop"
        }
        if searchable.contains("cross-artifact-evaluation") {
            return "evaluation"
        }
        return "artifact"
    }

    private func coverageDomain(
        for decisionKind: XcircuiteRunReviewDecisionActionKind
    ) -> String {
        switch decisionKind {
        case .approval:
            return "approval"
        case .waiver:
            return "waiver"
        case .resume:
            return "resume"
        }
    }

    private func appendRunManifestArtifacts(
        from ledger: FlowRunLedger,
        projectRoot: URL,
        into artifacts: inout [FlowRunReviewArtifact]
    ) {
        var seenPaths = Set(artifacts.map(\.path))
        for reference in ledger.runManifest.artifacts where seenPaths.insert(reference.path).inserted {
            artifacts.append(
                FlowRunReviewArtifact(
                    role: runReviewRole(for: reference),
                    artifactID: reference.artifactID,
                    path: reference.path,
                    kind: reference.kind,
                    format: reference.format,
                    sha256: reference.sha256,
                    byteCount: reference.byteCount,
                    integrity: artifactIntegrity(for: reference, projectRoot: projectRoot)
                )
            )
        }
    }

    private func runReviewRole(for reference: XcircuiteFileReference) -> String {
        if let role = retainedHistoryReviewRole(for: reference) {
            return role
        }
        if reference.artifactID?.hasSuffix("-edited-netlist") == true {
            return "planning-edited-netlist"
        }
        if reference.artifactID?.hasSuffix("-netlist-parameter-edit-report") == true {
            return "planning-netlist-parameter-edit-report"
        }
        if reference.artifactID?.hasSuffix("-attempts") == true {
            return "stage-attempts"
        }
        switch reference.artifactID {
        case "post-layout-comparison":
            return "post-layout-comparison"
        case "planning-action-domain-snapshot":
            return "planning-action-domain"
        case "planning-problem":
            return "planning-problem"
        case "planning-problem-translation-audit":
            return "planning-problem-translation-audit"
        case "planning-candidate-plan":
            return "planning-candidate-plan"
        case "planning-symbolic-planner-trace":
            return "planning-symbolic-planner-trace"
        case "planning-parameter-candidates":
            return "planning-parameter-candidates"
        case "planning-parameter-candidate-search-trace":
            return "planning-parameter-candidate-search-trace"
        case "planning-parameter-candidate-selection-trace":
            return "planning-parameter-candidate-selection-trace"
        case "planning-plan-verification":
            return "planning-plan-verification"
        case "planning-rejected-plans":
            return "planning-rejected-plans"
        case "planning-plan-execution":
            return "planning-plan-execution"
        case "flow-toolchain-profile":
            return "toolchain-profile"
        case "review-stage-artifact-ladder":
            return "stage-artifact-ladder"
        default:
            return "run-artifact"
        }
    }

    private func reviewItems(
        from ledger: FlowRunLedger,
        summary: FlowRunLedgerSummary,
        artifacts: [FlowRunReviewArtifact],
        projectRoot: URL,
        agentLoopSnapshot: XcircuiteAgentLoopSnapshot?,
        runGuardVerdict: XcircuiteRunGuardVerdict?,
        crossArtifactEvaluation: XcircuiteCrossArtifactEvaluation?
    ) -> [FlowRunReviewItem] {
        var items: [FlowRunReviewItem] = []
        let artifactPathsByStage = Dictionary(grouping: artifacts.filter { $0.stageID != nil }) { $0.stageID ?? "" }
            .mapValues { $0.map(\.path).sorted() }
        let artifactIntegrityIssuesByStage = Dictionary(
            grouping: artifacts.filter {
                $0.stageID != nil && isArtifactIntegrityIssue($0.integrity?.status)
            }
        ) { $0.stageID ?? "" }
        let runArtifactPaths = artifacts
            .filter { $0.stageID == nil }
            .map(\.path)
            .sorted()
        let approvalsByStage = Dictionary(uniqueKeysWithValues: ledger.approvals.map { ($0.stageID, $0) })

        if let diff = ledger.designDiff, diff.reviewState == .proposed {
            items.append(
                FlowRunReviewItem(
                    itemID: "review-design-diff",
                    kind: .designDiff,
                    status: .needsReview,
                    severity: .warning,
                    title: "Review proposed design diff",
                    reason: "A proposed design diff is waiting for human or policy review.",
                    artifactPaths: runArtifactPaths.filter { $0.hasSuffix("design-diff.json") },
                    nextActionID: "review-design-diff"
                )
            )
        }

        if let cancellation = ledger.cancellationRequest {
            items.append(
                FlowRunReviewItem(
                    itemID: "review-cancellation-request",
                    kind: .cancellation,
                    status: summary.status == .cancelled ? .informational : .needsReview,
                    severity: summary.status == .cancelled ? .info : .warning,
                    title: "Review cancellation request",
                    reason: "Cancellation requested by \(cancellation.requestedBy): \(cancellation.reason)",
                    artifactPaths: runArtifactPaths.filter { $0.hasSuffix(FlowRunProgressStore.cancellationRelativePath) },
                    nextActionID: "review-cancellation-request"
                )
            )
        }

        for stage in ledger.stages {
            let stageArtifactPaths = artifactPathsByStage[stage.stageID, default: []]
            let artifactIntegrityIssues = artifactIntegrityIssuesByStage[stage.stageID, default: []]
            if !artifactIntegrityIssues.isEmpty {
                let hasError = artifactIntegrityIssues.contains {
                    isArtifactIntegrityError($0.integrity?.status)
                }
                items.append(
                    FlowRunReviewItem(
                        itemID: stageScopedID(stage.stageID, "artifact-integrity"),
                        kind: .artifactIntegrity,
                        status: .needsRepair,
                        stageID: stage.stageID,
                        severity: hasError ? .error : .warning,
                        title: "Repair artifact integrity",
                        reason: "One or more stage artifacts could not be verified against the recorded run ledger.",
                        artifactPaths: artifactIntegrityIssues.map(\.path).sorted(),
                        nextActionID: stageScopedID(stage.stageID, "repair-artifact-integrity")
                    )
                )
            }

            for gate in stage.gates where isArtifactCoverageGate(gate) {
                items.append(
                    FlowRunReviewItem(
                        itemID: stageScopedID(stage.stageID, "repair-\(gate.gateID)"),
                        kind: .artifactCoverage,
                        status: .needsRepair,
                        stageID: stage.stageID,
                        severity: severity(for: gate),
                        title: "Repair artifact coverage",
                        reason: "The \(gate.gateID) gate reported that domain artifact manifests and flow ledger artifacts do not agree.",
                        diagnosticCodes: gate.diagnostics.map(\.code),
                        artifactPaths: stageArtifactPaths,
                        nextActionID: stageScopedID(stage.stageID, "repair-\(gate.gateID)")
                    )
                )
            }

            for gate in stage.gates where gate.gateID == "approval" && gate.status == .incomplete {
                let approval = approvalsByStage[stage.stageID]
                items.append(
                    FlowRunReviewItem(
                        itemID: approval == nil
                            ? stageScopedID(stage.stageID, "decide-approval")
                            : stageScopedID(stage.stageID, "resume-run"),
                        kind: .approvalGate,
                        status: approval == nil ? .needsReview : .readyToResume,
                        stageID: stage.stageID,
                        severity: approval == nil ? .warning : .info,
                        title: approval == nil ? "Decide approval gate" : "Resume after recorded approval decision",
                        reason: approval == nil
                            ? "The stage is waiting for a review decision."
                            : "A review decision is recorded; resume the run to apply the approval gate.",
                        diagnosticCodes: gate.diagnostics.map(\.code),
                        artifactPaths: stageArtifactPaths + approvalArtifactPaths(
                            runID: ledger.runID,
                            approval: approval
                        ),
                        nextActionID: approval == nil
                            ? stageScopedID(stage.stageID, "decide-approval")
                            : stageScopedID(stage.stageID, "resume-run")
                    )
                )
            }

            if stage.gates.contains(where: { $0.gateID == "tool-trust" && $0.status == .failed }) {
                items.append(
                    FlowRunReviewItem(
                        itemID: stageScopedID(stage.stageID, "repair-toolchain"),
                        kind: .toolTrust,
                        status: .needsRepair,
                        stageID: stage.stageID,
                        severity: .error,
                        title: "Repair tool trust gate",
                        reason: "The selected tool did not satisfy the trust gate.",
                        diagnosticCodes: diagnosticCodes(from: stage),
                        artifactPaths: stageArtifactPaths,
                        nextActionID: stageScopedID(stage.stageID, "repair-toolchain")
                    )
                )
            }

            switch stage.status {
            case .failed:
                items.append(
                    FlowRunReviewItem(
                        itemID: stageScopedID(stage.stageID, "inspect-failure"),
                        kind: .stageFailure,
                        status: .needsRepair,
                        stageID: stage.stageID,
                        severity: .error,
                        title: "Inspect failed stage",
                        reason: "The stage failed and needs diagnostic review before retry.",
                        diagnosticCodes: diagnosticCodes(from: stage),
                        artifactPaths: stageArtifactPaths,
                        nextActionID: stageScopedID(stage.stageID, "inspect-failure")
                    )
                )
            case .blocked:
                if !items.contains(where: { $0.stageID == stage.stageID }) {
                    items.append(
                        FlowRunReviewItem(
                            itemID: stageScopedID(stage.stageID, "resolve-blocker"),
                            kind: .stageBlocker,
                            status: .needsReview,
                            stageID: stage.stageID,
                            severity: .warning,
                            title: "Resolve blocked stage",
                            reason: "The stage is blocked and needs a concrete unblock action before retry.",
                            diagnosticCodes: diagnosticCodes(from: stage),
                            artifactPaths: stageArtifactPaths,
                            nextActionID: stageScopedID(stage.stageID, "resolve-blocker")
                        )
                    )
                }
            case .succeeded:
                let warningCodes = warningDiagnosticCodes(from: stage)
                if !warningCodes.isEmpty {
                    items.append(
                        FlowRunReviewItem(
                            itemID: stageScopedID(stage.stageID, "review-warnings"),
                            kind: .diagnosticReview,
                            status: .informational,
                            stageID: stage.stageID,
                            severity: .warning,
                            title: "Review stage warnings",
                            reason: "The stage succeeded with warnings that may affect the next design iteration.",
                            diagnosticCodes: warningCodes,
                            artifactPaths: stageArtifactPaths
                        )
                    )
                }
            case .pending, .running, .skipped:
                break
            }
        }
        items.append(contentsOf: planningCorrectnessReviewItems(
            from: artifacts,
            projectRoot: projectRoot
        ))
        items.append(contentsOf: problemTranslationAuditReviewItems(
            from: artifacts,
            projectRoot: projectRoot
        ))
        items.append(contentsOf: planningFeedbackReviewItems(from: artifacts))
        items.append(contentsOf: retainedHistoryReviewItems(
            from: artifacts,
            projectRoot: projectRoot
        ))
        items.append(contentsOf: loopAndEvaluationReviewItems(
            from: artifacts,
            agentLoopSnapshot: agentLoopSnapshot,
            runGuardVerdict: runGuardVerdict,
            crossArtifactEvaluation: crossArtifactEvaluation
        ))

        if items.isEmpty, summary.status == .succeeded {
            items.append(
                FlowRunReviewItem(
                    itemID: "archive-or-continue",
                    kind: .archiveOrContinue,
                    status: .informational,
                    severity: .info,
                    title: "Archive or continue",
                    reason: "The run succeeded; archive the artifacts or start the next design iteration.",
                    artifactPaths: artifacts.map(\.path).sorted(),
                    nextActionID: "archive-or-continue"
                )
            )
        }

        return items.sorted { left, right in
            if left.severity != right.severity {
                return severityRank(left.severity) > severityRank(right.severity)
            }
            return left.itemID < right.itemID
        }
    }

    private func retainedHistoryReviewRole(for reference: XcircuiteFileReference) -> String? {
        let searchable = [
            reference.artifactID ?? "",
            reference.path,
            reference.kind.rawValue,
            reference.format.rawValue,
        ]
        .joined(separator: " ")
        .lowercased()
        if searchable.contains("release-retention-index") {
            return "release-retention-index"
        }
        if searchable.contains("qualification-release-envelope")
            || searchable.contains("release-envelope") {
            return "release-envelope"
        }
        if searchable.contains("retained-ci-regression-budget") {
            return "retained-ci-regression-budget"
        }
        if searchable.contains("retention-index-review") {
            return "retention-index-review"
        }
        if searchable.contains("retention-index") {
            return "retention-index"
        }
        if searchable.contains("history-dashboard") {
            return "retained-history-dashboard"
        }
        if searchable.contains("history.jsonl") {
            return "retained-history"
        }
        if searchable.contains("workflow-run") || searchable.contains("workflow-report") {
            return "retained-workflow-report"
        }
        return nil
    }

    private func loopAndEvaluationReviewItems(
        from artifacts: [FlowRunReviewArtifact],
        agentLoopSnapshot: XcircuiteAgentLoopSnapshot?,
        runGuardVerdict: XcircuiteRunGuardVerdict?,
        crossArtifactEvaluation: XcircuiteCrossArtifactEvaluation?
    ) -> [FlowRunReviewItem] {
        var items: [FlowRunReviewItem] = []
        let loopArtifactPaths = artifacts
            .filter { artifact in
                artifact.role == "agent-loop-snapshot"
                    || artifact.role == "run-guard-verdict"
            }
            .map(\.path)
            .sorted()
        let crossArtifactPaths = artifacts
            .filter { $0.role == "cross-artifact-evaluation" }
            .map(\.path)
            .sorted()

        if let runGuardVerdict {
            let severity = severity(for: runGuardVerdict.status)
            let status = reviewStatus(for: runGuardVerdict.status)
            items.append(
                FlowRunReviewItem(
                    itemID: "review-run-guard",
                    kind: .runGuard,
                    status: status,
                    severity: severity,
                    title: "Review run guard verdict",
                    reason: runGuardReason(runGuardVerdict),
                    diagnosticCodes: runGuardVerdict.triggeredDetectors.flatMap(\.diagnosticCodes).sorted(),
                    artifactPaths: loopArtifactPaths,
                    nextActionID: runGuardVerdict.status == .continue ? nil : "review-run-guard"
                )
            )
        } else if let agentLoopSnapshot {
            let status = agentLoopSnapshot.resumeReadiness.status == .ready
                ? FlowRunReviewItemStatus.informational
                : .needsReview
            let severity = agentLoopSnapshot.resumeReadiness.status == .blocked
                ? FlowDiagnosticSeverity.error
                : agentLoopSnapshot.resumeReadiness.status == .ready ? .info : .warning
            items.append(
                FlowRunReviewItem(
                    itemID: "review-agent-loop-snapshot",
                    kind: .runGuard,
                    status: status,
                    severity: severity,
                    title: "Review loop snapshot",
                    reason: agentLoopSnapshot.resumeReadiness.reasons.isEmpty
                        ? "Loop snapshot is available for resume and evidence coverage review."
                        : agentLoopSnapshot.resumeReadiness.reasons.joined(separator: " "),
                    artifactPaths: loopArtifactPaths,
                    nextActionID: status == .informational ? nil : "review-agent-loop-snapshot"
                )
            )
        }

        if let crossArtifactEvaluation {
            let severity = severity(for: crossArtifactEvaluation.status)
            let status = reviewStatus(for: crossArtifactEvaluation.status)
            items.append(
                FlowRunReviewItem(
                    itemID: "review-cross-artifact-evaluation",
                    kind: .crossArtifactEvaluation,
                    status: status,
                    severity: severity,
                    title: "Review cross-artifact evaluation",
                    reason: crossArtifactEvaluation.summary.isEmpty
                        ? "Cross-artifact evaluation is available for review."
                        : crossArtifactEvaluation.summary,
                    diagnosticCodes: crossArtifactEvaluation.diagnostics.map(\.code).sorted(),
                    artifactPaths: crossArtifactPaths,
                    nextActionID: status == .informational ? nil : "review-cross-artifact-evaluation"
                )
            )
        }

        return items
    }

    private func runGuardReason(_ verdict: XcircuiteRunGuardVerdict) -> String {
        if verdict.triggeredDetectors.isEmpty {
            return "Run guard status is \(verdict.status.rawValue)."
        }
        let reasons = verdict.triggeredDetectors.map(\.reason)
        return reasons.joined(separator: " ")
    }

    private func reviewStatus(
        for status: XcircuiteRunGuardVerdict.Status
    ) -> FlowRunReviewItemStatus {
        switch status {
        case .continue:
            .informational
        case .needsHumanReview:
            .needsReview
        case .blocked, .cancelled:
            .needsRepair
        }
    }

    private func severity(
        for status: XcircuiteRunGuardVerdict.Status
    ) -> FlowDiagnosticSeverity {
        switch status {
        case .continue:
            .info
        case .needsHumanReview:
            .warning
        case .blocked, .cancelled:
            .error
        }
    }

    private func reviewStatus(
        for status: XcircuiteEvaluationStatus
    ) -> FlowRunReviewItemStatus {
        switch status {
        case .accepted:
            .informational
        case .needsHumanReview, .inconclusive:
            .needsReview
        case .rejected, .blocked:
            .needsRepair
        }
    }

    private func severity(
        for status: XcircuiteEvaluationStatus
    ) -> FlowDiagnosticSeverity {
        switch status {
        case .accepted:
            .info
        case .needsHumanReview, .inconclusive:
            .warning
        case .rejected, .blocked:
            .error
        }
    }

    private func retainedHistoryReviewItems(
        from artifacts: [FlowRunReviewArtifact],
        projectRoot: URL
    ) -> [FlowRunReviewItem] {
        let retainedArtifacts = artifacts
            .filter(isRetainedHistoryReviewArtifact)
            .sorted { left, right in left.path < right.path }
        guard !retainedArtifacts.isEmpty else {
            return []
        }
        var signal = RetainedHistoryReviewSignal()
        for artifact in retainedArtifacts {
            signal.artifactPaths.insert(artifact.path)
            guard artifact.format == .json else {
                continue
            }
            let url = projectRoot.appending(path: artifact.path)
            do {
                let data = try Data(contentsOf: url)
                let document = try JSONSerialization.jsonObject(with: data)
                collectRetainedHistoryReviewSignal(from: document, into: &signal)
            } catch {
                signal.needsReview = true
                signal.diagnosticCodes.insert("retained-history-artifact-unreadable")
            }
        }
        let status: FlowRunReviewItemStatus
        let severity: FlowDiagnosticSeverity
        let nextActionID: String?
        if signal.needsRepair {
            status = .needsRepair
            severity = .error
            nextActionID = "repair-retained-history-evidence"
        } else if signal.needsReview {
            status = .needsReview
            severity = .warning
            nextActionID = "review-retained-history-evidence"
        } else {
            status = .informational
            severity = .info
            nextActionID = nil
        }
        return [
            FlowRunReviewItem(
                itemID: "review-retained-history",
                kind: .retainedHistory,
                status: status,
                severity: severity,
                title: "Review retained CI history",
                reason: "Retained CI dashboard, history, retention index, workflow report, and release-gate artifacts are available for human and Agent review.",
                diagnosticCodes: signal.diagnosticCodes.sorted(),
                artifactPaths: retainedArtifacts.map(\.path),
                nextActionID: nextActionID
            ),
        ]
    }

    private func isRetainedHistoryReviewArtifact(_ artifact: FlowRunReviewArtifact) -> Bool {
        switch artifact.role {
        case "retained-history",
             "retained-history-dashboard",
             "retention-index",
             "retention-index-review",
             "retained-ci-regression-budget",
             "retained-workflow-report",
             "release-envelope",
             "release-retention-index":
            return true
        default:
            return false
        }
    }

    private func collectRetainedHistoryReviewSignal(
        from value: Any,
        into signal: inout RetainedHistoryReviewSignal
    ) {
        if let object = value as? [String: Any] {
            collectRetainedHistoryObjectSignal(from: object, into: &signal)
            for child in object.values {
                collectRetainedHistoryReviewSignal(from: child, into: &signal)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectRetainedHistoryReviewSignal(from: child, into: &signal)
            }
        }
    }

    private func collectRetainedHistoryObjectSignal(
        from object: [String: Any],
        into signal: inout RetainedHistoryReviewSignal
    ) {
        if let status = object["status"] as? String {
            if retainedHistoryStatusNeedsRepair(status) {
                signal.needsRepair = true
            } else if retainedHistoryStatusNeedsReview(status) {
                signal.needsReview = true
            }
        }
        if let code = object["code"] as? String {
            recordRetainedHistoryDiagnosticCode(code, into: &signal)
        }
        if let diagnosticCodes = object["diagnosticCodes"] as? [String] {
            for code in diagnosticCodes {
                recordRetainedHistoryDiagnosticCode(code, into: &signal)
            }
        }
        if let actionItems = object["actionItems"] as? [Any], !actionItems.isEmpty {
            signal.needsReview = true
        }
        if let failures = object["failures"] as? [Any], !failures.isEmpty {
            signal.needsRepair = true
        }
        if let requirements = object["requirements"] as? [[String: Any]] {
            collectRetainedHistoryRequirementSignals(from: requirements, into: &signal)
        }
    }

    private func collectRetainedHistoryRequirementSignals(
        from requirements: [[String: Any]],
        into signal: inout RetainedHistoryReviewSignal
    ) {
        for requirement in requirements {
            let required = requirement["required"] as? Bool ?? true
            if required, let status = requirement["status"] as? String, status != "passed" {
                signal.needsRepair = true
                if let requirementID = requirement["requirementID"] as? String {
                    signal.diagnosticCodes.insert("release-gate-requirement-blocked:\(requirementID)")
                }
            }
            if let diagnosticCodes = requirement["diagnosticCodes"] as? [String] {
                for code in diagnosticCodes {
                    recordRetainedHistoryDiagnosticCode(code, into: &signal)
                }
            }
        }
    }

    private func recordRetainedHistoryDiagnosticCode(
        _ code: String,
        into signal: inout RetainedHistoryReviewSignal
    ) {
        signal.diagnosticCodes.insert(code)
        if retainedHistoryCodeNeedsRepair(code) {
            signal.needsRepair = true
        } else {
            signal.needsReview = true
        }
    }

    private func retainedHistoryStatusNeedsRepair(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized == "failed"
            || normalized == "blocked"
            || normalized == "error"
            || normalized.contains("failed")
            || normalized.contains("blocked")
            || normalized.contains("regressed")
    }

    private func retainedHistoryStatusNeedsReview(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized == "needsreview"
            || normalized == "needs-review"
            || normalized == "needs_review"
            || normalized == "warning"
            || normalized == "incomplete"
    }

    private func retainedHistoryCodeNeedsRepair(_ code: String) -> Bool {
        let normalized = code.lowercased()
        return normalized.contains("stale")
            || normalized.contains("missing")
            || normalized.contains("mismatch")
            || normalized.contains("failed")
            || normalized.contains("failure")
            || normalized.contains("blocked")
            || normalized.contains("regressed")
            || normalized.contains("not-passed")
            || normalized.contains("too-low")
            || normalized.contains("exceeded")
    }

    private func planningCorrectnessReviewItems(
        from artifacts: [FlowRunReviewArtifact],
        projectRoot: URL
    ) -> [FlowRunReviewItem] {
        artifacts
            .filter { $0.role == "planning-plan-verification" }
            .flatMap { artifact in
                planVerificationCorrectnessItems(from: artifact, projectRoot: projectRoot)
            }
    }

    private func planningFeedbackReviewItems(
        from artifacts: [FlowRunReviewArtifact]
    ) -> [FlowRunReviewItem] {
        guard artifacts.contains(where: { $0.role == "planning-problem" }),
              let rejectedPlans = artifacts.first(where: { $0.role == "planning-rejected-plans" }) else {
            return []
        }
        return [
            FlowRunReviewItem(
                itemID: "planning-rejected-feedback",
                kind: .diagnosticReview,
                status: .needsReview,
                severity: .warning,
                title: "Regenerate candidate plan with feedback",
                reason: "Rejected planning feedback is available and should be folded into the next candidate-plan ranking.",
                diagnosticCodes: ["planning-rejected-feedback-available"],
                artifactPaths: [rejectedPlans.path],
                nextActionID: "regenerate-candidate-plan-with-feedback"
            ),
        ]
    }

    private func problemTranslationAuditReviewItems(
        from artifacts: [FlowRunReviewArtifact],
        projectRoot: URL
    ) -> [FlowRunReviewItem] {
        artifacts
            .filter { $0.role == "planning-problem-translation-audit" }
            .compactMap { artifact in
                problemTranslationAuditReviewItem(from: artifact, projectRoot: projectRoot)
            }
    }

    private func problemTranslationAuditReviewItem(
        from artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) -> FlowRunReviewItem? {
        let url = projectRoot.appending(path: artifact.path)
        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(FlowRunProblemTranslationAuditDocument.self, from: data)
            guard document.blocking else {
                return nil
            }
            return FlowRunReviewItem(
                itemID: "planning-problem-translation-audit-blocking",
                kind: .planningCorrectness,
                status: .needsRepair,
                severity: problemTranslationAuditSeverity(from: document),
                title: "Repair problem translation audit",
                reason: document.summary,
                diagnosticCodes: document.diagnosticCodes,
                artifactPaths: [artifact.path],
                nextActionID: document.primaryNextAction
            )
        } catch {
            return FlowRunReviewItem(
                itemID: "planning-problem-translation-audit-unreadable",
                kind: .planningCorrectness,
                status: .needsReview,
                severity: .warning,
                title: "Review problem translation audit",
                reason: "The problem translation audit artifact could not be decoded for review.",
                diagnosticCodes: ["problem-translation-audit-unreadable"],
                artifactPaths: [artifact.path],
                nextActionID: "regenerate-problem-translation-audit"
            )
        }
    }

    private func problemTranslationAuditSeverity(
        from document: FlowRunProblemTranslationAuditDocument
    ) -> FlowDiagnosticSeverity {
        document.diagnostics.contains { $0.severity == "error" } ? .error : .warning
    }

    private func planVerificationCorrectnessItems(
        from artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) -> [FlowRunReviewItem] {
        let url = projectRoot.appending(path: artifact.path)
        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(PlanVerificationReviewDocument.self, from: data)
            return document.correctnessGateResults.compactMap { gate in
                planningCorrectnessReviewItem(from: gate, artifact: artifact)
            }
        } catch {
            return [
                FlowRunReviewItem(
                    itemID: "planning-correctness-unreadable",
                    kind: .planningCorrectness,
                    status: .needsReview,
                    severity: .warning,
                    title: "Review planning correctness evidence",
                    reason: "The planning verification artifact could not be decoded for correctness gate review.",
                    diagnosticCodes: ["planning-correctness-unreadable"],
                    artifactPaths: [artifact.path],
                    nextActionID: "regenerate-plan-verification"
                ),
            ]
        }
    }

    private func planningCorrectnessReviewItem(
        from gate: PlanVerificationCorrectnessGate,
        artifact: FlowRunReviewArtifact
    ) -> FlowRunReviewItem? {
        guard gate.status != "passed" else {
            return nil
        }
        return FlowRunReviewItem(
            itemID: "planning-correctness-\(gate.gateID)",
            kind: .planningCorrectness,
            status: planningCorrectnessReviewStatus(from: gate.status),
            severity: planningCorrectnessSeverity(from: gate.status),
            title: planningCorrectnessTitle(for: gate),
            reason: gate.summary,
            diagnosticCodes: gate.diagnostics.map(\.code),
            artifactPaths: [artifact.path],
            nextActionID: gate.nextActions.first
        )
    }

    private func planningCorrectnessReviewStatus(
        from status: String
    ) -> FlowRunReviewItemStatus {
        switch status {
        case "failed", "blocked":
            .needsRepair
        case "pending", "not-evaluated":
            .needsReview
        default:
            .informational
        }
    }

    private func planningCorrectnessSeverity(
        from status: String
    ) -> FlowDiagnosticSeverity {
        switch status {
        case "failed":
            .error
        case "blocked", "pending", "not-evaluated":
            .warning
        default:
            .info
        }
    }

    private func planningCorrectnessTitle(
        for gate: PlanVerificationCorrectnessGate
    ) -> String {
        "Review planning correctness: \(gate.gateID)"
    }

    private func approvalArtifactPaths(
        runID: String,
        approval: XcircuiteApprovalRecord?
    ) -> [String] {
        guard let approval else {
            return []
        }
        guard let path = identifierPolicy.approvalArtifactPath(
            runID: runID,
            stageID: approval.stageID
        ) else {
            return []
        }
        return [path]
    }

    private func appendOptionalRunArtifact(
        role: String,
        runID: String,
        relativePath: String,
        projectRoot: URL,
        recordedReferencesByPath: [String: XcircuiteFileReference],
        into artifacts: inout [FlowRunReviewArtifact]
    ) {
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(relativePath)"
        let existsInLedger = recordedReferencesByPath[projectRelativePath] != nil
        let existsOnDisk: Bool
        do {
            let url = try XcircuitePackage(projectRoot: projectRoot)
                .url(forProjectRelativePath: projectRelativePath)
            existsOnDisk = FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        } catch {
            existsOnDisk = false
        }
        guard existsInLedger || existsOnDisk else {
            return
        }
        guard !artifacts.contains(where: { $0.path == projectRelativePath }) else {
            return
        }
        artifacts.append(
            runArtifact(
                role: role,
                runID: runID,
                relativePath: relativePath,
                projectRoot: projectRoot,
                recordedReferencesByPath: recordedReferencesByPath
            )
        )
    }

    private func loadOptionalRunJSON<T: Decodable>(
        _ type: T.Type,
        runID: String,
        relativePath: String,
        projectRoot: URL
    ) throws -> T? {
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(relativePath)"
        let url = try XcircuitePackage(projectRoot: projectRoot)
            .url(forProjectRelativePath: projectRelativePath)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return try XcircuitePackageStore().readJSON(type, from: url)
    }

    private func runArtifact(
        role: String,
        runID: String,
        relativePath: String,
        projectRoot: URL,
        recordedReferencesByPath: [String: XcircuiteFileReference],
        stageID: String? = nil,
        kind: XcircuiteFileKind = .report,
        format: XcircuiteFileFormat = .json
    ) -> FlowRunReviewArtifact {
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(relativePath)"
        let artifactID = role
        let artifactURL: URL
        do {
            artifactURL = try XcircuitePackage(projectRoot: projectRoot)
                .url(forProjectRelativePath: projectRelativePath)
        } catch {
            return FlowRunReviewArtifact(
                role: role,
                artifactID: artifactID,
                stageID: stageID,
                path: projectRelativePath,
                kind: kind,
                format: format,
                integrity: FlowRunReviewArtifactIntegrity(
                    status: .invalidPath,
                    message: "Artifact path is not safe for project-relative resolution: \(error)"
                )
            )
        }
        if let reference = recordedReferencesByPath[projectRelativePath] {
            return FlowRunReviewArtifact(
                role: role,
                artifactID: reference.artifactID ?? artifactID,
                stageID: stageID,
                path: projectRelativePath,
                kind: reference.kind,
                format: reference.format,
                sha256: reference.sha256,
                byteCount: reference.byteCount,
                integrity: artifactIntegrity(for: reference, stageID: stageID, projectRoot: projectRoot)
            )
        }
        let path = artifactURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return FlowRunReviewArtifact(
                role: role,
                artifactID: artifactID,
                stageID: stageID,
                path: projectRelativePath,
                kind: kind,
                format: format,
                integrity: FlowRunReviewArtifactIntegrity(
                    status: .missingArtifact,
                    message: "Artifact file is missing."
                )
            )
        }
        do {
            let data = try Data(contentsOf: artifactURL)
            let sha256 = XcircuiteHasher().sha256(data: data)
            let byteCount = Int64(data.count)
            return FlowRunReviewArtifact(
                role: role,
                artifactID: artifactID,
                stageID: stageID,
                path: projectRelativePath,
                kind: kind,
                format: format,
                sha256: sha256,
                byteCount: byteCount,
                integrity: FlowRunReviewArtifactIntegrity(
                    status: .noRecordedReference,
                    actualSHA256: sha256,
                    actualByteCount: byteCount,
                    message: "Artifact exists, but no recorded file reference is available for independent integrity verification."
                )
            )
        } catch {
            return FlowRunReviewArtifact(
                role: role,
                artifactID: artifactID,
                stageID: stageID,
                path: projectRelativePath,
                kind: kind,
                format: format,
                integrity: FlowRunReviewArtifactIntegrity(
                    status: .unreadableArtifact,
                    message: "Artifact file could not be read: \(error)"
                )
            )
        }
    }

    private func artifactIntegrity(
        for reference: XcircuiteFileReference,
        stageID: String? = nil,
        projectRoot: URL
    ) -> FlowRunReviewArtifactIntegrity {
        if let stageID, !identifierPolicy.isValidStageID(stageID) {
            return identifierPolicy.invalidStageIdentifierIntegrity(stageID)
        }
        if let artifactID = reference.artifactID,
           !identifierPolicy.isValidArtifactID(artifactID) {
            return identifierPolicy.invalidArtifactIdentifierIntegrity(artifactID)
        }
        let packageIntegrity = XcircuiteFileReferenceVerifier().verify(
            reference,
            projectRoot: projectRoot
        )
        return FlowRunReviewArtifactIntegrity(
            status: reviewIntegrityStatus(from: packageIntegrity.status),
            expectedSHA256: packageIntegrity.expectedSHA256,
            actualSHA256: packageIntegrity.actualSHA256,
            expectedByteCount: packageIntegrity.expectedByteCount,
            actualByteCount: packageIntegrity.actualByteCount,
            message: packageIntegrity.message
        )
    }

    private func reviewIntegrityStatus(
        from status: XcircuiteFileReferenceIntegrityStatus
    ) -> FlowRunReviewArtifactIntegrityStatus {
        switch status {
        case .verified:
            .verified
        case .missingArtifact:
            .missingArtifact
        case .missingDigest:
            .missingDigest
        case .missingByteCount:
            .missingByteCount
        case .invalidDigest:
            .invalidDigest
        case .invalidByteCount:
            .invalidByteCount
        case .byteCountMismatch:
            .byteCountMismatch
        case .sha256Mismatch:
            .sha256Mismatch
        case .invalidPath:
            .invalidPath
        case .unreadableArtifact:
            .unreadableArtifact
        }
    }

    private func stageScopedID(_ stageID: String, _ suffix: String) -> String {
        identifierPolicy.safeStageScopedID(stageID: stageID, suffix: suffix)
    }

    private func isArtifactIntegrityIssue(_ status: FlowRunReviewArtifactIntegrityStatus?) -> Bool {
        guard let status else {
            return false
        }
        return status != .verified
    }

    private func isArtifactCoverageGate(_ gate: FlowGateResult) -> Bool {
        guard gate.status == .failed || gate.status == .incomplete || gate.status == .blocked else {
            return false
        }
        return gate.gateID.hasSuffix("-artifacts")
    }

    private func severity(for gate: FlowGateResult) -> FlowDiagnosticSeverity {
        gate.status == .failed ? .error : .warning
    }

    private func isArtifactIntegrityError(_ status: FlowRunReviewArtifactIntegrityStatus?) -> Bool {
        switch status {
        case .missingArtifact, .invalidDigest, .invalidByteCount, .byteCountMismatch, .sha256Mismatch,
             .invalidIdentifier, .noRecordedReference, .invalidPath, .unreadableArtifact:
            true
        case .missingDigest, .missingByteCount, .verified, nil:
            false
        }
    }

    private func diagnosticCodes(from stage: FlowStageResult) -> [String] {
        stage.diagnostics.map(\.code) + stage.gates.flatMap { $0.diagnostics.map(\.code) }
    }

    private func warningDiagnosticCodes(from stage: FlowStageResult) -> [String] {
        let stageWarnings = stage.diagnostics
            .filter { $0.severity == .warning }
            .map(\.code)
        let gateWarnings = stage.gates.flatMap { gate in
            gate.diagnostics
                .filter { $0.severity == .warning }
                .map(\.code)
        }
        return stageWarnings + gateWarnings
    }

    private func severityRank(_ severity: FlowDiagnosticSeverity) -> Int {
        switch severity {
        case .error:
            3
        case .warning:
            2
        case .info:
            1
        }
    }
}

private struct PlanVerificationReviewDocument: Decodable {
    var correctnessGateResults: [PlanVerificationCorrectnessGate]
}

private struct PlanVerificationCorrectnessGate: Decodable {
    var gateID: String
    var status: String
    var summary: String
    var diagnostics: [PlanVerificationCorrectnessDiagnostic]
    var nextActions: [String]

}

private struct PlanVerificationCorrectnessDiagnostic: Decodable {
    var code: String
}

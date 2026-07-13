import Foundation
import ToolQualification

public struct DefaultFlowRunLedgerSummarizer: FlowRunLedgerSummarizing {
    private let identifierPolicy = FlowRunReviewIdentifierPolicy()

    public init() {}

    public func summarize(_ ledger: FlowRunLedger) -> FlowRunLedgerSummary {
        FlowRunLedgerSummary(
            runID: ledger.runID,
            status: ledger.runResult.status,
            runDirectoryPath: ledger.runDirectory.path(percentEncoded: false),
            stages: stageSummaries(from: ledger.stages),
            toolchain: toolchainSummary(from: ledger.toolchain),
            designDiff: designDiffSummary(from: ledger.designDiff),
            progressEventCount: ledger.progressEvents.count,
            latestProgressEvent: ledger.progressEvents.last,
            cancellationRequest: ledger.cancellationRequest,
            actionCount: ledger.actions.count,
            approvalCount: ledger.approvals.count,
            diagnostics: diagnostics(from: ledger.stages),
            nextActions: nextActions(from: ledger),
            suggestedCommandSelections: ledger.suggestedCommandSelections
        )
    }

    private func stageSummaries(from stages: [FlowStageResult]) -> [FlowRunStageSummary] {
        stages.map { stage in
            FlowRunStageSummary(
                stageID: stage.stageID,
                status: stage.status,
                gates: stage.gates.map { gate in
                    FlowRunGateSummary(
                        gateID: gate.gateID,
                        status: gate.status,
                        diagnosticCodes: gate.diagnostics.map(\.code)
                    )
                },
                diagnosticCodes: stage.diagnostics.map(\.code),
                artifactCount: stage.artifacts.count,
                attemptCount: stage.attempts.count,
                retryCount: max(0, stage.attempts.count - 1)
            )
        }
    }

    private func toolchainSummary(from manifest: FlowToolchainManifest?) -> FlowRunToolchainSummary? {
        guard let manifest else {
            return nil
        }

        let selectedToolIDs = Set(manifest.stages.compactMap(\.selectedToolID)).sorted()
        let rejectedEvaluationCount = manifest.stages.reduce(0) { count, stage in
            count + stage.evaluations.filter { $0.decision.status == .rejected }.count
        }
        let missingSelectionStageIDs = manifest.stages
            .filter { $0.requiredTool != nil && $0.selectedToolID == nil }
            .map(\.stageID)
            .sorted()

        return FlowRunToolchainSummary(
            stageCount: manifest.stages.count,
            selectedToolIDs: selectedToolIDs,
            rejectedEvaluationCount: rejectedEvaluationCount,
            missingSelectionStageIDs: missingSelectionStageIDs,
            profileID: manifest.profile?.profileID,
            pdkID: manifest.profile?.pdkID,
            technologyCatalogID: manifest.profile?.technologyCatalogID,
            technologyCatalogPath: manifest.profile?.technologyCatalogPath,
            profileArtifactPath: manifest.profile?.profileArtifactPath
        )
    }

    private func designDiffSummary(from diff: XcircuiteDesignDiff?) -> FlowRunDesignDiffSummary? {
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

    private func diagnostics(from stages: [FlowStageResult]) -> [FlowDiagnostic] {
        stages.flatMap { stage in
            stage.diagnostics + stage.gates.flatMap(\.diagnostics)
        }
    }

    private func nextActions(from ledger: FlowRunLedger) -> [FlowRunNextAction] {
        var actions: [FlowRunNextAction] = []
        let approvedOrRejectedStageIDs = Set(ledger.approvals.map(\.stageID))

        if let diff = ledger.designDiff, diff.reviewState == .proposed {
            actions.append(
                FlowRunNextAction(
                    actionID: "review-design-diff",
                    kind: "reviewDesignDiff",
                    severity: .warning,
                    reason: "A proposed design diff is waiting for human or policy review.",
                    diagnosticCodes: []
                )
            )
        }

        if let cancellation = ledger.cancellationRequest {
            actions.append(
                FlowRunNextAction(
                    actionID: "review-cancellation-request",
                    kind: "reviewCancellation",
                    severity: ledger.runResult.status == .cancelled ? .info : .warning,
                    reason: "A run cancellation request is recorded by \(cancellation.requestedBy): \(cancellation.reason)",
                    diagnosticCodes: []
                )
            )
        }

        for stage in ledger.stages {
            actions.append(
                contentsOf: nextActions(
                    for: stage,
                    approvedOrRejectedStageIDs: approvedOrRejectedStageIDs
                )
            )
        }
        actions.append(contentsOf: planningCorrectnessActions(from: ledger))
        actions.append(contentsOf: problemTranslationAuditActions(from: ledger))
        if let feedbackAction = planningFeedbackAction(from: ledger) {
            actions.append(feedbackAction)
        }

        if actions.isEmpty, ledger.runResult.status == .succeeded {
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
        approvedOrRejectedStageIDs: Set<String>
    ) -> [FlowRunNextAction] {
        var actions: [FlowRunNextAction] = []

        for gate in stage.gates where gate.status == .incomplete && gate.gateID == "approval" {
            if approvedOrRejectedStageIDs.contains(stage.stageID) {
                actions.append(
                    FlowRunNextAction(
                        actionID: stageScopedID(stage.stageID, "resume-run"),
                        kind: "resumeRun",
                        stageID: stage.stageID,
                        severity: .info,
                        reason: "A review decision is recorded; resume the run to apply the approval gate.",
                        diagnosticCodes: gate.diagnostics.map(\.code)
                    )
                )
            } else {
                actions.append(
                    FlowRunNextAction(
                        actionID: stageScopedID(stage.stageID, "decide-approval"),
                        kind: "decideApproval",
                        stageID: stage.stageID,
                        severity: .warning,
                        reason: "The stage is waiting for a review decision.",
                        diagnosticCodes: gate.diagnostics.map(\.code)
                    )
                )
            }
        }

        if stage.gates.contains(where: { $0.gateID == "tool-trust" && $0.status == .failed }) {
            actions.append(
                FlowRunNextAction(
                    actionID: stageScopedID(stage.stageID, "repair-toolchain"),
                    kind: "repairToolchain",
                    stageID: stage.stageID,
                    severity: .error,
                    reason: "The selected tool did not satisfy the trust gate.",
                    diagnosticCodes: diagnosticCodes(from: stage)
                )
            )
        }

        if stage.attempts.count > 1 {
            actions.append(
                FlowRunNextAction(
                    actionID: stageScopedID(stage.stageID, "review-retry-attempts"),
                    kind: "reviewRetryAttempts",
                    stageID: stage.stageID,
                    severity: stage.status == .failed ? .warning : .info,
                    reason: "The stage has recorded retry attempts that should be reviewed before changing policy or inputs.",
                    diagnosticCodes: diagnosticCodes(from: stage)
                )
            )
        }

        actions.append(contentsOf: artifactCoverageActions(for: stage))

        switch stage.status {
        case .failed:
            actions.append(
                FlowRunNextAction(
                    actionID: stageScopedID(stage.stageID, "inspect-failure"),
                    kind: "inspectFailure",
                    stageID: stage.stageID,
                    severity: .error,
                    reason: "The stage failed and needs diagnostic review before retry.",
                    diagnosticCodes: diagnosticCodes(from: stage)
                )
            )
        case .blocked:
            if !actions.contains(where: { $0.stageID == stage.stageID }) {
                actions.append(
                    FlowRunNextAction(
                        actionID: stageScopedID(stage.stageID, "resolve-blocker"),
                        kind: "resolveBlocker",
                        stageID: stage.stageID,
                        severity: .warning,
                        reason: "The stage is blocked and needs a concrete unblock action before retry.",
                        diagnosticCodes: diagnosticCodes(from: stage)
                    )
                )
            }
        case .pending, .running, .succeeded, .skipped:
            break
        }

        return actions
    }

    private func artifactCoverageActions(for stage: FlowStageResult) -> [FlowRunNextAction] {
        stage.gates
            .filter { isArtifactCoverageGate($0) }
            .map { gate in
                FlowRunNextAction(
                    actionID: stageScopedID(stage.stageID, "repair-\(gate.gateID)"),
                    kind: "repairArtifactCoverage",
                    stageID: stage.stageID,
                    severity: severity(for: gate),
                    reason: "The \(gate.gateID) gate reported that domain artifact manifests and flow ledger artifacts do not agree.",
                    diagnosticCodes: gate.diagnostics.map(\.code)
                )
            }
    }

    private func isArtifactCoverageGate(_ gate: FlowGateResult) -> Bool {
        guard gate.status == .failed || gate.status == .incomplete || gate.status == .blocked else {
            return false
        }
        return gate.gateID.hasSuffix("-artifacts")
    }

    private func severity(for gate: FlowGateResult) -> FlowDiagnosticSeverity {
        gate.status == .failed || gate.status == .blocked ? .error : .warning
    }

    private func diagnosticCodes(from stage: FlowStageResult) -> [String] {
        stage.diagnostics.map(\.code) + stage.gates.flatMap { $0.diagnostics.map(\.code) }
    }

    private func planningCorrectnessActions(from ledger: FlowRunLedger) -> [FlowRunNextAction] {
        let projectRoot = projectRoot(fromRunDirectory: ledger.runDirectory)
        return ledger.runManifest.artifacts
            .filter(isPlanningPlanVerificationArtifact)
            .flatMap { reference in
                planningCorrectnessActions(
                    from: reference,
                    projectRoot: projectRoot,
                    runID: ledger.runID
                )
            }
    }

    private func isPlanningPlanVerificationArtifact(_ reference: XcircuiteFileReference) -> Bool {
        reference.artifactID == "planning-plan-verification"
            || reference.path.hasSuffix("/planning/plan-verification.json")
    }

    private func problemTranslationAuditActions(from ledger: FlowRunLedger) -> [FlowRunNextAction] {
        let projectRoot = projectRoot(fromRunDirectory: ledger.runDirectory)
        return ledger.runManifest.artifacts
            .filter(isProblemTranslationAuditArtifact)
            .compactMap { reference in
                problemTranslationAuditAction(
                    from: reference,
                    projectRoot: projectRoot,
                    runID: ledger.runID
                )
            }
    }

    private func isProblemTranslationAuditArtifact(_ reference: XcircuiteFileReference) -> Bool {
        reference.artifactID == "planning-problem-translation-audit"
            || reference.path.hasSuffix("/planning/problem-translation-audit.json")
    }

    private func problemTranslationAuditAction(
        from reference: XcircuiteFileReference,
        projectRoot: URL,
        runID: String
    ) -> FlowRunNextAction? {
        let url = projectRoot.appending(path: reference.path)
        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(FlowRunProblemTranslationAuditDocument.self, from: data)
            guard document.blocking else {
                return nil
            }
            let nextActions = document.nextActions.isEmpty
                ? ["repair-problem-translation-audit"]
                : document.nextActions
            return FlowRunNextAction(
                actionID: document.primaryNextAction,
                kind: "repairProblemTranslationAudit",
                severity: problemTranslationAuditSeverity(from: document),
                reason: document.summary,
                diagnosticCodes: document.diagnosticCodes,
                suggestedCommands: suggestedCommands(
                    forPlanningNextActions: nextActions,
                    projectRoot: projectRoot,
                    runID: runID
                )
            )
        } catch {
            return FlowRunNextAction(
                actionID: "regenerate-problem-translation-audit",
                kind: "auditProblemTranslation",
                severity: .warning,
                reason: "The problem translation audit artifact could not be decoded for summary next-action generation.",
                diagnosticCodes: ["problem-translation-audit-unreadable"],
                suggestedCommands: [
                    xcircuiteFlowCommand(
                        commandID: "xcircuite-flow.audit-problem-translation",
                        readiness: .ready,
                        commandName: "audit-problem-translation",
                        projectRoot: projectRoot,
                        runID: runID,
                        extraArguments: [],
                        reason: "Regenerate planning/problem-translation-audit.json from the current planning problem."
                    ),
                ]
            )
        }
    }

    private func problemTranslationAuditSeverity(
        from document: FlowRunProblemTranslationAuditDocument
    ) -> FlowDiagnosticSeverity {
        document.diagnostics.contains { $0.severity == "error" } ? .error : .warning
    }

    private func planningFeedbackAction(from ledger: FlowRunLedger) -> FlowRunNextAction? {
        let projectRoot = projectRoot(fromRunDirectory: ledger.runDirectory)
        guard hasArtifact("planning-problem", in: ledger.runManifest),
              let rejectedPlans = artifact("planning-rejected-plans", in: ledger.runManifest),
              hasFeedbackPayload(rejectedPlans, projectRoot: projectRoot) else {
            return nil
        }
        return FlowRunNextAction(
            actionID: "regenerate-candidate-plan-with-feedback",
            kind: "regenerateCandidatePlanWithFeedback",
            severity: .warning,
            reason: "Rejected planning feedback is available; regenerate the candidate plan so symbolic and numeric ranking can avoid repeated failures.",
            diagnosticCodes: ["planning-rejected-feedback-available"],
            suggestedCommands: [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.generate-candidate-plan.with-rejected-feedback",
                    readiness: .ready,
                    commandName: "generate-candidate-plan",
                    projectRoot: projectRoot,
                    runID: ledger.runID,
                    extraArguments: [
                        "--rejected-plans-artifact-id",
                        "planning-rejected-plans",
                    ],
                    reason: "Regenerate planning/candidate-plan.json using recorded rejected-plan feedback."
                ),
            ]
        )
    }

    private func artifact(
        _ artifactID: String,
        in manifest: XcircuiteRunManifest
    ) -> XcircuiteFileReference? {
        manifest.artifacts.first { $0.artifactID == artifactID }
    }

    private func hasArtifact(_ artifactID: String, in manifest: XcircuiteRunManifest) -> Bool {
        artifact(artifactID, in: manifest) != nil
    }

    private func hasFeedbackPayload(
        _ reference: XcircuiteFileReference,
        projectRoot: URL
    ) -> Bool {
        if let byteCount = reference.byteCount, byteCount > 0 {
            return true
        }
        let url = projectRoot.appending(path: reference.path)
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return false
        }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func planningCorrectnessActions(
        from reference: XcircuiteFileReference,
        projectRoot: URL,
        runID: String
    ) -> [FlowRunNextAction] {
        let url = projectRoot.appending(path: reference.path)
        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(PlanVerificationSummaryDocument.self, from: data)
            return document.correctnessGateResults.compactMap { gate in
                planningCorrectnessAction(from: gate, projectRoot: projectRoot, runID: runID)
            }
        } catch {
            return [
                FlowRunNextAction(
                    actionID: "regenerate-plan-verification",
                    kind: "regeneratePlanningVerification",
                    severity: .warning,
                    reason: "The planning verification artifact could not be decoded for summary next-action generation.",
                    diagnosticCodes: ["planning-correctness-unreadable"],
                    suggestedCommands: [
                        xcircuiteFlowCommand(
                            commandID: "xcircuite-flow.verify-candidate-plan",
                            readiness: .ready,
                            commandName: "verify-candidate-plan",
                            projectRoot: projectRoot,
                            runID: runID,
                            extraArguments: [],
                            reason: "Regenerate planning/plan-verification.json from the current candidate plan."
                        ),
                    ]
                ),
            ]
        }
    }

    private func planningCorrectnessAction(
        from gate: PlanVerificationSummaryCorrectnessGate,
        projectRoot: URL,
        runID: String
    ) -> FlowRunNextAction? {
        guard gate.status != "passed" else {
            return nil
        }

        return FlowRunNextAction(
            actionID: gate.nextActions.first ?? "planning-correctness-\(gate.gateID)",
            kind: planningCorrectnessActionKind(from: gate.status),
            severity: planningCorrectnessSeverity(from: gate.status),
            reason: gate.summary,
            diagnosticCodes: gate.diagnostics.map(\.code),
            suggestedCommands: suggestedCommands(
                forPlanningNextActions: gate.nextActions,
                projectRoot: projectRoot,
                runID: runID
            )
        )
    }

    private func planningCorrectnessActionKind(from status: String) -> String {
        switch status {
        case "failed", "blocked":
            "repairPlanningCorrectness"
        case "pending", "not-evaluated":
            "verifyPlanningCorrectness"
        default:
            "reviewPlanningCorrectness"
        }
    }

    private func planningCorrectnessSeverity(from status: String) -> FlowDiagnosticSeverity {
        switch status {
        case "failed":
            .error
        case "blocked", "pending", "not-evaluated":
            .warning
        default:
            .info
        }
    }

    private func projectRoot(fromRunDirectory runDirectory: URL) -> URL {
        runDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func suggestedCommands(
        forPlanningNextActions nextActions: [String],
        projectRoot: URL,
        runID: String
    ) -> [FlowRunSuggestedCommand] {
        var commands: [FlowRunSuggestedCommand] = []
        var seenCommandIDs: Set<String> = []

        for nextAction in nextActions {
            for command in suggestedCommands(
                forPlanningNextAction: nextAction,
                projectRoot: projectRoot,
                runID: runID
            ) where seenCommandIDs.insert(command.commandID).inserted {
                commands.append(command)
            }
        }

        return commands
    }

    private func suggestedCommands(
        forPlanningNextAction nextAction: String,
        projectRoot: URL,
        runID: String
    ) -> [FlowRunSuggestedCommand] {
        switch nextAction {
        case "audit-problem-translation":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.audit-problem-translation",
                    readiness: .ready,
                    commandName: "audit-problem-translation",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: [],
                    reason: "Audit source-to-problem translation coverage and persist planning/problem-translation-audit.json."
                ),
            ]
        case "validate-planning-problem":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.validate-planning-problem",
                    readiness: .ready,
                    commandName: "validate-planning-problem",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: [],
                    reason: "Validate planning/problem.json and persist planning/problem-validation.json."
                ),
            ]
        case "generate-candidate-plan":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.generate-candidate-plan",
                    readiness: .ready,
                    commandName: "generate-candidate-plan",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: [],
                    reason: "Generate planning/candidate-plan.json from the current planning problem."
                ),
            ]
        case "execute-candidate-plan":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.execute-candidate-plan",
                    readiness: .ready,
                    commandName: "execute-candidate-plan",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: [],
                    reason: "Execute the current candidate plan and persist plan-execution artifacts."
                ),
            ]
        case "verify-candidate-plan":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.verify-candidate-plan",
                    readiness: .ready,
                    commandName: "verify-candidate-plan",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: [],
                    reason: "Run preflight candidate-plan verification."
                ),
            ]
        case "verify-candidate-plan:post-execution":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.verify-candidate-plan.post-execution",
                    readiness: .ready,
                    commandName: "verify-candidate-plan",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: ["--mode", "post-execution"],
                    reason: "Run post-execution candidate-plan verification against produced artifacts."
                ),
            ]
        case "generate-parameter-candidates":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.generate-parameter-candidates",
                    readiness: .ready,
                    commandName: "generate-parameter-candidates",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: [],
                    reason: "Generate bounded parameter candidates from planning/problem.json."
                ),
            ]
        case "synthesize-parameter-candidate-plan":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.synthesize-parameter-candidate-plan",
                    readiness: .ready,
                    commandName: "synthesize-parameter-candidate-plan",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: [],
                    reason: "Synthesize the selected parameter candidate into planning/candidate-plan.json."
                ),
            ]
        case "run-numeric-repair-loop":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.run-numeric-repair-loop",
                    readiness: .ready,
                    commandName: "run-numeric-repair-loop",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: [],
                    reason: "Run the numeric repair loop over parameter candidates, execution, and verification."
                ),
            ]
        case "repair-planning-problem-goals", "add-objective-goal-atoms":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.validate-planning-problem.after-goal-edit",
                    readiness: .requiresInput,
                    commandName: "validate-planning-problem",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: [],
                    reason: "Edit planning/problem.json goal atoms first, then validate the repaired problem."
                ),
            ]
        case "repair-problem-translation-audit",
             "attach-objective-source-ref",
             "attach-constraint-source-ref",
             "attach-action-source-objective",
             "attach-goal-atom-source-objective",
             "map-source-ref-to-objective-or-constraint",
             "regenerate-planning-problem":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.audit-problem-translation.after-translation-repair",
                    readiness: .requiresInput,
                    commandName: "audit-problem-translation",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: [],
                    reason: "Repair planning/problem.json translation provenance first, then rerun the translation audit."
                ),
            ]
        case "add-verification-gates":
            return [
                xcircuiteFlowCommand(
                    commandID: "xcircuite-flow.verify-candidate-plan.post-execution.after-gate-edit",
                    readiness: .requiresInput,
                    commandName: "verify-candidate-plan",
                    projectRoot: projectRoot,
                    runID: runID,
                    extraArguments: ["--mode", "post-execution"],
                    reason: "Add required verification gates first, then rerun post-execution verification."
                ),
            ]
        default:
            if nextAction.hasPrefix("repair-verification-gate:") {
                return [
                    xcircuiteFlowCommand(
                        commandID: "xcircuite-flow.verify-candidate-plan.post-execution.after-gate-repair",
                        readiness: .requiresInput,
                        commandName: "verify-candidate-plan",
                        projectRoot: projectRoot,
                        runID: runID,
                        extraArguments: ["--mode", "post-execution"],
                        reason: "Repair the failing verification gate evidence first, then rerun post-execution verification."
                    ),
                ]
            }
            return []
        }
    }

    private func xcircuiteFlowCommand(
        commandID: String,
        readiness: FlowRunSuggestedCommandReadiness,
        commandName: String,
        projectRoot: URL,
        runID: String,
        extraArguments: [String],
        reason: String
    ) -> FlowRunSuggestedCommand {
        FlowRunSuggestedCommand(
            commandID: commandID,
            readiness: readiness,
            executable: "xcircuite-flow",
            arguments: [
                commandName,
                "--project-root",
                normalizedPath(projectRoot),
                "--run-id",
                runID,
            ] + extraArguments + ["--pretty"],
            reason: reason
        )
    }

    private func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private func stageScopedID(_ stageID: String, _ suffix: String) -> String {
        identifierPolicy.safeStageScopedID(stageID: stageID, suffix: suffix)
    }
}

private struct PlanVerificationSummaryDocument: Decodable {
    var correctnessGateResults: [PlanVerificationSummaryCorrectnessGate]
}

private struct PlanVerificationSummaryCorrectnessGate: Decodable {
    var gateID: String
    var status: String
    var summary: String
    var diagnostics: [PlanVerificationSummaryDiagnostic]
    var nextActions: [String]

}

private struct PlanVerificationSummaryDiagnostic: Decodable {
    var code: String
}

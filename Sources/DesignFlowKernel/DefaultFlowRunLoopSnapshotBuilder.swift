import CircuiteFoundation
import Foundation

public struct DefaultFlowRunLoopSnapshotBuilder: Sendable {
    private let loader: any FlowRunLedgerLoading
    private let evidencePersistence: any FlowRunEvidencePersisting

    public init(
        loader: any FlowRunLedgerLoading,
        evidencePersistence: any FlowRunEvidencePersisting
    ) {
        self.loader = loader
        self.evidencePersistence = evidencePersistence
    }

    public func summarizeLoop(
        runID: String,
        workspaceID: FlowWorkspaceID,
        profile: FlowAgentLoopProfile = .makeDefault(),
        generatedAt: Date = Date(),
        persist: Bool = true
    ) async throws -> FlowRunLoopSummaryResult {
        try FlowAgentLoopProfileValidator().validate(profile)
        let ledger = try await loader.loadRunLedger(runID: runID)
        let envelopeRecords = try await evidencePersistence.loadArtifactEnvelopeRecords(
            runID: runID
        )
        let envelopes = envelopeRecords.map(\.envelope)
        let persistedAtByArtifactID = Dictionary(
            envelopeRecords.map { ($0.envelope.reference.id.rawValue, $0.persistedAt) },
            uniquingKeysWith: max
        )
        let artifactReferences = try availableArtifactReferences(from: ledger, envelopes: envelopes)
        let iterations = buildIterations(from: ledger, envelopes: envelopes)
        let snapshot = try buildSnapshot(
            from: ledger,
            profile: profile,
            iterations: iterations,
            artifactReferences: artifactReferences,
            envelopes: envelopes,
            generatedAt: generatedAt,
            persistedAtByArtifactID: persistedAtByArtifactID
        )

        var producedReferences: [ArtifactReference] = []
        if persist {
            let iterationsReference = try await evidencePersistence.persistLoopIterationSummaries(
                iterations,
                runID: runID
            )
            producedReferences.append(iterationsReference)
            let snapshotReference = try await evidencePersistence.persistAgentLoopSnapshot(snapshot)
            producedReferences.append(snapshotReference)
        }

        return FlowRunLoopSummaryResult(
            runID: runID,
            profileID: profile.profileID,
            iterations: iterations,
            snapshot: snapshot,
            artifactReferences: producedReferences
        )
    }

    private func buildIterations(
        from ledger: FlowRunLedger,
        envelopes: [FlowArtifactEnvelope]
    ) -> [FlowLoopIterationSummary] {
        let iterationActions = ledger.actions.filter { action in
            !action.actionKind.hasPrefix("review.")
                && !action.actionKind.hasPrefix("release.")
        }
        guard !iterationActions.isEmpty else {
            return []
        }

        var grouped: [(iterationID: String, actions: [FlowRunActionRecord])] = []
        for (index, action) in iterationActions.enumerated() {
            let iterationID = action.context.iterationID ?? "iteration-\(index + 1)"
            if let existingIndex = grouped.firstIndex(where: { $0.iterationID == iterationID }) {
                grouped[existingIndex].actions.append(action)
            } else {
                grouped.append((iterationID: iterationID, actions: [action]))
            }
        }

        return grouped.enumerated().map { index, group in
            let actions = group.actions
            let inputArtifactIDs = stableUnique(
                actions.flatMap { $0.inputs.compactMap(\.artifactID) }
            )
            let outputArtifactIDs = stableUnique(
                actions.flatMap { $0.outputs.compactMap(\.artifactID) }
            )
            return FlowLoopIterationSummary(
                iterationID: group.iterationID,
                runID: ledger.runID,
                ordinal: index + 1,
                status: iterationStatus(actions.map(\.status)),
                actionIDs: actions.map(\.actionID),
                actionKinds: stableUnique(actions.map(\.actionKind)),
                startedAt: actions.map(\.createdAt).min(),
                completedAt: actions.map(\.createdAt).max(),
                inputArtifactIDs: inputArtifactIDs,
                outputArtifactIDs: outputArtifactIDs,
                designDiffID: ledger.designDiff == nil ? nil : "design-diff",
                evaluationDelta: evaluationDelta(
                    envelopes: envelopes,
                    outputArtifactIDs: Set(outputArtifactIDs),
                    actions: actions
                ),
                riskSignals: actionRiskSignals(actions)
            )
        }
    }

    private func buildSnapshot(
        from ledger: FlowRunLedger,
        profile: FlowAgentLoopProfile,
        iterations: [FlowLoopIterationSummary],
        artifactReferences: [ArtifactReference],
        envelopes: [FlowArtifactEnvelope],
        generatedAt: Date,
        persistedAtByArtifactID: [String: Date]
    ) throws -> FlowAgentLoopSnapshot {
        let evidenceCoverage = try evidenceCoverage(
            profile: profile,
            artifactReferences: artifactReferences,
            envelopes: envelopes,
            generatedAt: generatedAt,
            persistedAtByArtifactID: persistedAtByArtifactID
        )
        let approvalState = approvalState(from: ledger)
        let budgetUsage = budgetUsage(from: ledger, profile: profile)
        let metricTrend = metricTrend(from: envelopes)
        let diagnosticTrend = diagnosticTrend(from: ledger)
        let resumeReadiness = resumeReadiness(
            runStatus: ledger.runManifest.status,
            evidenceCoverage: evidenceCoverage,
            budgetUsage: budgetUsage,
            approvalState: approvalState
        )

        return FlowAgentLoopSnapshot(
            snapshotID: "snapshot-\(ledger.runID)",
            runID: ledger.runID,
            profileID: profile.profileID,
            latestIterationID: iterations.last?.iterationID,
            generatedAt: generatedAt,
            actionCount: ledger.actions.count,
            artifactCount: artifactReferences.count,
            budgetUsage: budgetUsage,
            evidenceCoverage: evidenceCoverage,
            metricTrend: metricTrend,
            diagnosticTrend: diagnosticTrend,
            approvalState: approvalState,
            resumeReadiness: resumeReadiness
        )
    }

    private func availableArtifactReferences(
        from ledger: FlowRunLedger,
        envelopes: [FlowArtifactEnvelope]
    ) throws -> [ArtifactReference] {
        var references: [ArtifactReference] = []
        references.append(contentsOf: ledger.runManifest.artifacts)
        references.append(contentsOf: ledger.stages
            .flatMap(\.artifacts)
            .map { $0 })
        references.append(contentsOf: envelopes.map(\.reference))
        return stableUniqueReferences(references)
    }

    private func budgetUsage(
        from ledger: FlowRunLedger,
        profile: FlowAgentLoopProfile
    ) -> FlowAgentLoopSnapshot.BudgetUsage {
        let actionCount = ledger.actions.count
        let elapsedSeconds = elapsedSeconds(from: ledger.actions)
        let toolInvocationCount = ledger.actions.count
        let changedFileCount = Set(ledger.designDiff?.changes.map(\.path) ?? []).count
        let designChangeCount = ledger.designDiff?.changes.count ?? 0
        var exceeded: [String] = []
        appendExceeded(&exceeded, id: "maxActions", value: actionCount, limit: profile.budgets.maxActions)
        appendExceeded(&exceeded, id: "maxElapsedSeconds", value: elapsedSeconds, limit: profile.budgets.maxElapsedSeconds)
        appendExceeded(&exceeded, id: "maxToolInvocations", value: toolInvocationCount, limit: profile.budgets.maxToolInvocations)
        appendExceeded(&exceeded, id: "maxChangedFiles", value: changedFileCount, limit: profile.budgets.maxChangedFiles)
        appendExceeded(&exceeded, id: "maxDesignChanges", value: designChangeCount, limit: profile.budgets.maxDesignChanges)
        return FlowAgentLoopSnapshot.BudgetUsage(
            actionCount: actionCount,
            maxActions: profile.budgets.maxActions,
            elapsedSeconds: elapsedSeconds,
            maxElapsedSeconds: profile.budgets.maxElapsedSeconds,
            toolInvocationCount: toolInvocationCount,
            maxToolInvocations: profile.budgets.maxToolInvocations,
            changedFileCount: changedFileCount,
            maxChangedFiles: profile.budgets.maxChangedFiles,
            designChangeCount: designChangeCount,
            maxDesignChanges: profile.budgets.maxDesignChanges,
            exceededBudgetIDs: exceeded
        )
    }

    private func evidenceCoverage(
        profile: FlowAgentLoopProfile,
        artifactReferences: [ArtifactReference],
        envelopes: [FlowArtifactEnvelope],
        generatedAt: Date,
        persistedAtByArtifactID: [String: Date]
    ) throws -> FlowAgentLoopSnapshot.EvidenceCoverage {
        let availableArtifactIDs = stableUnique(
            artifactReferences.compactMap(\.artifactID) + envelopes.map(\.artifactID)
        )
        let items = try profile.requiredEvidence.map { requiredEvidence in
            try evidenceCoverageItem(
                requiredEvidence,
                artifactReferences: artifactReferences,
                envelopes: envelopes,
                generatedAt: generatedAt,
                persistedAtByArtifactID: persistedAtByArtifactID
            )
        }
        let requiredItems = items.filter { item in
            item.status != .optionalMissing
        }
        return FlowAgentLoopSnapshot.EvidenceCoverage(
            requiredCount: profile.requiredEvidence.filter(\.required).count,
            satisfiedCount: requiredItems.filter { $0.status == .satisfied }.count,
            missingCount: requiredItems.filter { $0.status == .missing }.count,
            staleCount: requiredItems.filter { $0.status == .stale }.count,
            availableArtifactIDs: availableArtifactIDs,
            items: items
        )
    }

    private func evidenceCoverageItem(
        _ requiredEvidence: FlowAgentLoopProfile.RequiredEvidence,
        artifactReferences: [ArtifactReference],
        envelopes: [FlowArtifactEnvelope],
        generatedAt: Date,
        persistedAtByArtifactID: [String: Date]
    ) throws -> FlowAgentLoopSnapshot.EvidenceCoverage.Item {
        let matchingEnvelopes = envelopes.filter { envelope in
            evidenceMatches(requiredEvidence, envelope: envelope)
        }
        let matchingReferences = stableUniqueReferences(
            matchingEnvelopes.map(\.reference) + artifactReferences.filter { reference in
                evidenceMatches(requiredEvidence, reference: reference)
            }
        )
        let foundationMatchingReferences = matchingReferences
        guard !matchingReferences.isEmpty else {
            return FlowAgentLoopSnapshot.EvidenceCoverage.Item(
                evidenceID: requiredEvidence.evidenceID,
                artifactRole: requiredEvidence.artifactRole,
                artifactID: requiredEvidence.artifactID,
                stageID: requiredEvidence.stageID,
                status: requiredEvidence.required ? .missing : .optionalMissing,
                reason: "required evidence is not present"
            )
        }
        if let maximumAgeSeconds = requiredEvidence.maximumAgeSeconds,
           matchingReferences.contains(where: {
               isStale(
                   $0,
                   maximumAgeSeconds: maximumAgeSeconds,
                   generatedAt: generatedAt,
                   persistedAtByArtifactID: persistedAtByArtifactID
               )
           }) {
            return FlowAgentLoopSnapshot.EvidenceCoverage.Item(
                evidenceID: requiredEvidence.evidenceID,
                artifactRole: requiredEvidence.artifactRole,
                artifactID: requiredEvidence.artifactID,
                stageID: requiredEvidence.stageID,
                status: .stale,
                artifactReferences: foundationMatchingReferences,
                reason: "evidence exceeded maximumAgeSeconds"
            )
        }
        return FlowAgentLoopSnapshot.EvidenceCoverage.Item(
            evidenceID: requiredEvidence.evidenceID,
            artifactRole: requiredEvidence.artifactRole,
            artifactID: requiredEvidence.artifactID,
            stageID: requiredEvidence.stageID,
            status: .satisfied,
            artifactReferences: foundationMatchingReferences
        )
    }

    private func evidenceMatches(
        _ requiredEvidence: FlowAgentLoopProfile.RequiredEvidence,
        envelope: FlowArtifactEnvelope
    ) -> Bool {
        if let stageID = requiredEvidence.stageID, envelope.stageID != stageID {
            return false
        }
        if let artifactID = requiredEvidence.artifactID {
            return envelope.artifactID == artifactID || envelope.reference.artifactID == artifactID
        }
        return envelope.role == requiredEvidence.artifactRole
            || envelope.artifactID == requiredEvidence.artifactRole
            || envelope.reference.artifactID == requiredEvidence.artifactRole
    }

    private func evidenceMatches(
        _ requiredEvidence: FlowAgentLoopProfile.RequiredEvidence,
        reference: ArtifactReference
    ) -> Bool {
        if let artifactID = requiredEvidence.artifactID {
            return reference.artifactID == artifactID
        }
        return reference.artifactID == requiredEvidence.artifactRole
            || reference.path.contains(requiredEvidence.artifactRole)
    }

    private func metricTrend(
        from envelopes: [FlowArtifactEnvelope]
    ) -> FlowAgentLoopSnapshot.MetricTrend {
        var accepted = 0
        var rejected = 0
        var needsReview = 0
        var blocked = 0
        var inconclusive = 0
        var channelIDs: [String] = []
        for envelope in envelopes {
            if let result = envelope.evaluationResult {
                increment(
                    status: result.status,
                    accepted: &accepted,
                    rejected: &rejected,
                    needsReview: &needsReview,
                    blocked: &blocked,
                    inconclusive: &inconclusive
                )
                for channelResult in result.channelResults {
                    channelIDs.append(channelResult.channelID)
                    increment(
                        status: channelResult.status,
                        accepted: &accepted,
                        rejected: &rejected,
                        needsReview: &needsReview,
                        blocked: &blocked,
                        inconclusive: &inconclusive
                    )
                }
            }
            channelIDs.append(contentsOf: envelope.observationSet?.channels.map(\.channelID) ?? [])
        }
        return FlowAgentLoopSnapshot.MetricTrend(
            acceptedCount: accepted,
            rejectedCount: rejected,
            needsHumanReviewCount: needsReview,
            blockedCount: blocked,
            inconclusiveCount: inconclusive,
            channelIDs: stableUnique(channelIDs)
        )
    }

    private func diagnosticTrend(from ledger: FlowRunLedger) -> FlowAgentLoopSnapshot.DiagnosticTrend {
        let diagnostics = allDiagnostics(from: ledger)
        let failedCount = diagnostics.filter { $0.severity == .error }.count
        let counts = Dictionary(grouping: diagnostics.map(\.code), by: { $0 })
            .mapValues(\.count)
        let repeated = counts.filter { $0.value > 1 }
        return FlowAgentLoopSnapshot.DiagnosticTrend(
            diagnosticCount: diagnostics.count,
            failedDiagnosticCount: failedCount,
            repeatedCodes: repeated,
            newestCodes: stableUnique(diagnostics.suffix(10).map(\.code))
        )
    }

    private func approvalState(from ledger: FlowRunLedger) -> FlowAgentLoopSnapshot.ApprovalState {
        let rejected = ledger.approvals
            .filter { $0.verdict == .rejected }
            .map(\.stageID)
        let approved = ledger.approvals
            .filter { $0.verdict == .approved || $0.verdict == .waived }
            .map(\.stageID)
        let decided = Set(rejected + approved)
        let pending = ledger.stages
            .filter { $0.status == .blocked && !decided.contains($0.stageID) }
            .map(\.stageID)
        let status: FlowAgentLoopSnapshot.ApprovalState.Status
        if !rejected.isEmpty {
            status = .rejected
        } else if !pending.isEmpty {
            status = .pending
        } else if !approved.isEmpty {
            status = .approved
        } else {
            status = .notRequired
        }
        return FlowAgentLoopSnapshot.ApprovalState(
            status: status,
            pendingStageIDs: stableUnique(pending),
            approvedStageIDs: stableUnique(approved),
            rejectedStageIDs: stableUnique(rejected)
        )
    }

    private func resumeReadiness(
        runStatus: FlowRunStatus,
        evidenceCoverage: FlowAgentLoopSnapshot.EvidenceCoverage,
        budgetUsage: FlowAgentLoopSnapshot.BudgetUsage,
        approvalState: FlowAgentLoopSnapshot.ApprovalState
    ) -> FlowAgentLoopSnapshot.ResumeReadiness {
        var reasons: [String] = []
        if runStatus == .cancelled {
            return FlowAgentLoopSnapshot.ResumeReadiness(
                status: .blocked,
                reasons: ["run is cancelled"]
            )
        }
        if approvalState.status == .rejected {
            reasons.append("approval was rejected")
        }
        if approvalState.status == .pending {
            reasons.append("approval is pending")
        }
        if evidenceCoverage.missingCount > 0 {
            reasons.append("required evidence is missing")
        }
        if evidenceCoverage.staleCount > 0 {
            reasons.append("required evidence is stale")
        }
        if !budgetUsage.exceededBudgetIDs.isEmpty {
            reasons.append("loop budget is exceeded")
        }
        if approvalState.status == .rejected {
            return FlowAgentLoopSnapshot.ResumeReadiness(status: .blocked, reasons: reasons)
        }
        if !reasons.isEmpty {
            return FlowAgentLoopSnapshot.ResumeReadiness(status: .needsHumanReview, reasons: reasons)
        }
        return FlowAgentLoopSnapshot.ResumeReadiness(status: .ready)
    }

    private func evaluationDelta(
        envelopes: [FlowArtifactEnvelope],
        outputArtifactIDs: Set<String>,
        actions: [FlowRunActionRecord]
    ) -> FlowLoopIterationSummary.EvaluationDelta {
        let scopedEnvelopes = envelopes.filter { envelope in
            outputArtifactIDs.contains(envelope.artifactID)
                || outputArtifactIDs.contains(envelope.reference.artifactID)
        }
        let selectedEnvelopes = scopedEnvelopes.isEmpty ? [] : scopedEnvelopes
        var accepted = 0
        var rejected = 0
        var needsReview = 0
        var blocked = 0
        var inconclusive = 0
        var channelIDs: [String] = []
        for envelope in selectedEnvelopes {
            if let result = envelope.evaluationResult {
                increment(
                    status: result.status,
                    accepted: &accepted,
                    rejected: &rejected,
                    needsReview: &needsReview,
                    blocked: &blocked,
                    inconclusive: &inconclusive
                )
                for channel in result.channelResults {
                    channelIDs.append(channel.channelID)
                }
            }
            channelIDs.append(contentsOf: envelope.observationSet?.channels.map(\.channelID) ?? [])
        }
        let failedDiagnostics = actions.flatMap(\.diagnostics).filter { $0.severity == .error }.count
        return FlowLoopIterationSummary.EvaluationDelta(
            acceptedCount: accepted,
            rejectedCount: rejected,
            needsHumanReviewCount: needsReview,
            blockedCount: blocked,
            inconclusiveCount: inconclusive,
            failedDiagnosticCount: failedDiagnostics,
            changedMetricIDs: stableUnique(channelIDs)
        )
    }

    private func actionRiskSignals(
        _ actions: [FlowRunActionRecord]
    ) -> [FlowLoopIterationSummary.RiskSignal] {
        actions.flatMap { action in
            action.diagnostics.enumerated().compactMap { index, diagnostic in
                let severity = guardSeverity(diagnostic.severity)
                guard severity >= .warning else {
                    return nil
                }
                return FlowLoopIterationSummary.RiskSignal(
                    signalID: "\(action.actionID)-diagnostic-\(index)",
                    detectorID: "actionDiagnostic",
                    severity: severity,
                    reason: diagnostic.message,
                    actionIDs: [action.actionID],
                    artifactIDs: action.outputs.compactMap(\.artifactID),
                    diagnosticCode: diagnostic.code
                )
            }
        }
    }

    private func iterationStatus(_ statuses: [FlowRunActionStatus]) -> FlowLoopIterationSummary.Status {
        if statuses.contains(.blocked) {
            return .blocked
        }
        if statuses.contains(.failed) {
            return .failed
        }
        if statuses.contains(.cancelled) {
            return .cancelled
        }
        if statuses.contains(.running) {
            return .running
        }
        if statuses.contains(.partial) {
            return .partial
        }
        if statuses.contains(.succeeded) {
            return .succeeded
        }
        return .unknown
    }

    private func allDiagnostics(from ledger: FlowRunLedger) -> [FlowRunDiagnostic] {
        var diagnostics = ledger.actions.flatMap(\.diagnostics)
        diagnostics.append(contentsOf: ledger.stages.flatMap(\.diagnostics).map(runActionDiagnostic))
        diagnostics.append(contentsOf: ledger.stages.flatMap(\.gates).flatMap(\.diagnostics).map(runActionDiagnostic))
        return diagnostics
    }

    private func runActionDiagnostic(_ diagnostic: FlowDiagnostic) -> FlowRunDiagnostic {
        FlowRunDiagnostic(
            severity: runActionSeverity(diagnostic.severity),
            code: diagnostic.code,
            message: diagnostic.message
        )
    }

    private func runActionSeverity(_ severity: FlowDiagnosticSeverity) -> FlowRunDiagnosticSeverity {
        switch severity {
        case .info:
            .info
        case .warning:
            .warning
        case .error:
            .error
        }
    }

    private func guardSeverity(_ severity: FlowRunDiagnosticSeverity) -> FlowRunGuardSeverity {
        switch severity {
        case .info:
            .info
        case .warning:
            .warning
        case .error:
            .error
        }
    }

    private func increment(
        status: FlowEvaluationStatus,
        accepted: inout Int,
        rejected: inout Int,
        needsReview: inout Int,
        blocked: inout Int,
        inconclusive: inout Int
    ) {
        switch status {
        case .accepted:
            accepted += 1
        case .rejected:
            rejected += 1
        case .needsHumanReview:
            needsReview += 1
        case .blocked:
            blocked += 1
        case .inconclusive:
            inconclusive += 1
        }
    }

    private func appendExceeded(_ values: inout [String], id: String, value: Int?, limit: Int?) {
        guard let value, let limit, value > limit else {
            return
        }
        values.append(id)
    }

    private func elapsedSeconds(from actions: [FlowRunActionRecord]) -> Int? {
        guard let first = actions.map(\.createdAt).min(),
              let last = actions.map(\.createdAt).max() else {
            return nil
        }
        return max(0, Int(last.timeIntervalSince(first)))
    }

    private func isStale(
        _ reference: ArtifactReference,
        maximumAgeSeconds: Int,
        generatedAt: Date,
        persistedAtByArtifactID: [String: Date]
    ) -> Bool {
        guard let persistedAt = persistedAtByArtifactID[reference.id.rawValue] else {
            return true
        }
        return generatedAt.timeIntervalSince(persistedAt) > Double(maximumAgeSeconds)
    }

    private func stableUniqueReferences(_ references: [ArtifactReference]) -> [ArtifactReference] {
        var seen: Set<String> = []
        var result: [ArtifactReference] = []
        for reference in references {
            let key = reference.artifactID
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(reference)
        }
        return result.sorted { left, right in
            left.artifactID < right.artifactID
        }
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

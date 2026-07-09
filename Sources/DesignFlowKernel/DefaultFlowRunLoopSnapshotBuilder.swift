import Foundation
import XcircuitePackage

public struct DefaultFlowRunLoopSnapshotBuilder: Sendable {
    private let loader: any FlowRunLedgerLoading
    private let packageStore: XcircuitePackageStore

    public init(
        loader: any FlowRunLedgerLoading = FlowRunLedgerLoader(),
        packageStore: XcircuitePackageStore = XcircuitePackageStore()
    ) {
        self.loader = loader
        self.packageStore = packageStore
    }

    public func summarizeLoop(
        runID: String,
        projectRoot: URL,
        profile: XcircuiteAgentLoopProfile = .makeDefault(),
        generatedAt: Date = Date(),
        persist: Bool = true
    ) throws -> FlowRunLoopSummaryResult {
        try XcircuiteAgentLoopProfileValidator().validate(profile)
        let ledger = try loader.loadRunLedger(runID: runID, projectRoot: projectRoot)
        let envelopes = try loadArtifactEnvelopes(from: ledger)
        let artifactReferences = availableArtifactReferences(from: ledger, envelopes: envelopes)
        let iterations = buildIterations(from: ledger, envelopes: envelopes)
        let snapshot = buildSnapshot(
            from: ledger,
            profile: profile,
            iterations: iterations,
            artifactReferences: artifactReferences,
            envelopes: envelopes,
            generatedAt: generatedAt,
            projectRoot: projectRoot
        )

        var producedReferences: [XcircuiteFileReference] = []
        if persist {
            producedReferences.append(
                try packageStore.writeLoopIterationSummaries(
                    iterations,
                    runID: runID,
                    inProjectAt: projectRoot
                )
            )
            producedReferences.append(
                try packageStore.writeAgentLoopSnapshot(snapshot, inProjectAt: projectRoot)
            )
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
        envelopes: [XcircuiteArtifactEnvelope]
    ) -> [XcircuiteLoopIterationSummary] {
        guard !ledger.actions.isEmpty else {
            return []
        }

        var grouped: [(iterationID: String, actions: [XcircuiteRunActionRecord])] = []
        for (index, action) in ledger.actions.enumerated() {
            let iterationID = stringMetadata("iterationID", in: action.metadata)
                ?? "iteration-\(index + 1)"
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
            return XcircuiteLoopIterationSummary(
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
                riskSignals: actionRiskSignals(actions),
                metadata: [
                    "actionCount": .number(Double(actions.count)),
                ]
            )
        }
    }

    private func buildSnapshot(
        from ledger: FlowRunLedger,
        profile: XcircuiteAgentLoopProfile,
        iterations: [XcircuiteLoopIterationSummary],
        artifactReferences: [XcircuiteFileReference],
        envelopes: [XcircuiteArtifactEnvelope],
        generatedAt: Date,
        projectRoot: URL
    ) -> XcircuiteAgentLoopSnapshot {
        let evidenceCoverage = evidenceCoverage(
            profile: profile,
            artifactReferences: artifactReferences,
            envelopes: envelopes,
            generatedAt: generatedAt,
            projectRoot: projectRoot
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

        return XcircuiteAgentLoopSnapshot(
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
            resumeReadiness: resumeReadiness,
            metadata: [
                "stageCount": .number(Double(ledger.stages.count)),
                "evidenceEnvelopeCount": .number(Double(envelopes.count)),
            ]
        )
    }

    private func loadArtifactEnvelopes(from ledger: FlowRunLedger) throws -> [XcircuiteArtifactEnvelope] {
        let evidenceDirectory = ledger.runDirectory.appending(path: "evidence")
        guard directoryExists(evidenceDirectory) else {
            return []
        }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: evidenceDirectory,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw XcircuitePackageError.readFailed(
                "evidence: \(error.localizedDescription)"
            )
        }
        var envelopes: [XcircuiteArtifactEnvelope] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard url.lastPathComponent.hasSuffix("-envelope.json") else {
                continue
            }
            envelopes.append(try packageStore.readJSON(XcircuiteArtifactEnvelope.self, from: url))
        }
        return envelopes
    }

    private func availableArtifactReferences(
        from ledger: FlowRunLedger,
        envelopes: [XcircuiteArtifactEnvelope]
    ) -> [XcircuiteFileReference] {
        var references: [XcircuiteFileReference] = []
        references.append(contentsOf: ledger.runManifest.artifacts)
        references.append(contentsOf: ledger.stages.flatMap(\.artifacts))
        references.append(contentsOf: envelopes.map(\.reference))
        return stableUniqueReferences(references)
    }

    private func budgetUsage(
        from ledger: FlowRunLedger,
        profile: XcircuiteAgentLoopProfile
    ) -> XcircuiteAgentLoopSnapshot.BudgetUsage {
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
        return XcircuiteAgentLoopSnapshot.BudgetUsage(
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
        profile: XcircuiteAgentLoopProfile,
        artifactReferences: [XcircuiteFileReference],
        envelopes: [XcircuiteArtifactEnvelope],
        generatedAt: Date,
        projectRoot: URL
    ) -> XcircuiteAgentLoopSnapshot.EvidenceCoverage {
        let availableArtifactIDs = stableUnique(
            artifactReferences.compactMap(\.artifactID) + envelopes.map(\.artifactID)
        )
        let items = profile.requiredEvidence.map { requiredEvidence in
            evidenceCoverageItem(
                requiredEvidence,
                artifactReferences: artifactReferences,
                envelopes: envelopes,
                generatedAt: generatedAt,
                projectRoot: projectRoot
            )
        }
        let requiredItems = items.filter { item in
            item.status != .optionalMissing
        }
        return XcircuiteAgentLoopSnapshot.EvidenceCoverage(
            requiredCount: profile.requiredEvidence.filter(\.required).count,
            satisfiedCount: requiredItems.filter { $0.status == .satisfied }.count,
            missingCount: requiredItems.filter { $0.status == .missing }.count,
            staleCount: requiredItems.filter { $0.status == .stale }.count,
            availableArtifactIDs: availableArtifactIDs,
            items: items
        )
    }

    private func evidenceCoverageItem(
        _ requiredEvidence: XcircuiteAgentLoopProfile.RequiredEvidence,
        artifactReferences: [XcircuiteFileReference],
        envelopes: [XcircuiteArtifactEnvelope],
        generatedAt: Date,
        projectRoot: URL
    ) -> XcircuiteAgentLoopSnapshot.EvidenceCoverage.Item {
        let matchingEnvelopes = envelopes.filter { envelope in
            evidenceMatches(requiredEvidence, envelope: envelope)
        }
        let matchingReferences = stableUniqueReferences(
            matchingEnvelopes.map(\.reference) + artifactReferences.filter { reference in
                evidenceMatches(requiredEvidence, reference: reference)
            }
        )
        guard !matchingReferences.isEmpty else {
            return XcircuiteAgentLoopSnapshot.EvidenceCoverage.Item(
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
               isStale($0, maximumAgeSeconds: maximumAgeSeconds, generatedAt: generatedAt, projectRoot: projectRoot)
           }) {
            return XcircuiteAgentLoopSnapshot.EvidenceCoverage.Item(
                evidenceID: requiredEvidence.evidenceID,
                artifactRole: requiredEvidence.artifactRole,
                artifactID: requiredEvidence.artifactID,
                stageID: requiredEvidence.stageID,
                status: .stale,
                artifactReferences: matchingReferences,
                reason: "evidence exceeded maximumAgeSeconds"
            )
        }
        return XcircuiteAgentLoopSnapshot.EvidenceCoverage.Item(
            evidenceID: requiredEvidence.evidenceID,
            artifactRole: requiredEvidence.artifactRole,
            artifactID: requiredEvidence.artifactID,
            stageID: requiredEvidence.stageID,
            status: .satisfied,
            artifactReferences: matchingReferences
        )
    }

    private func evidenceMatches(
        _ requiredEvidence: XcircuiteAgentLoopProfile.RequiredEvidence,
        envelope: XcircuiteArtifactEnvelope
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
        _ requiredEvidence: XcircuiteAgentLoopProfile.RequiredEvidence,
        reference: XcircuiteFileReference
    ) -> Bool {
        if let artifactID = requiredEvidence.artifactID {
            return reference.artifactID == artifactID
        }
        return reference.artifactID == requiredEvidence.artifactRole
            || reference.path.contains(requiredEvidence.artifactRole)
    }

    private func metricTrend(
        from envelopes: [XcircuiteArtifactEnvelope]
    ) -> XcircuiteAgentLoopSnapshot.MetricTrend {
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
        return XcircuiteAgentLoopSnapshot.MetricTrend(
            acceptedCount: accepted,
            rejectedCount: rejected,
            needsHumanReviewCount: needsReview,
            blockedCount: blocked,
            inconclusiveCount: inconclusive,
            channelIDs: stableUnique(channelIDs)
        )
    }

    private func diagnosticTrend(from ledger: FlowRunLedger) -> XcircuiteAgentLoopSnapshot.DiagnosticTrend {
        let diagnostics = allDiagnostics(from: ledger)
        let failedCount = diagnostics.filter { $0.severity == .error }.count
        let counts = Dictionary(grouping: diagnostics.map(\.code), by: { $0 })
            .mapValues(\.count)
        let repeated = counts.filter { $0.value > 1 }
        return XcircuiteAgentLoopSnapshot.DiagnosticTrend(
            diagnosticCount: diagnostics.count,
            failedDiagnosticCount: failedCount,
            repeatedCodes: repeated,
            newestCodes: stableUnique(diagnostics.suffix(10).map(\.code))
        )
    }

    private func approvalState(from ledger: FlowRunLedger) -> XcircuiteAgentLoopSnapshot.ApprovalState {
        let rejected = ledger.approvals
            .filter { $0.verdict == .rejected }
            .map(\.stageID)
        let approved = ledger.approvals
            .filter { $0.verdict == .approved }
            .map(\.stageID)
        let decided = Set(rejected + approved)
        let pending = ledger.stages
            .filter { $0.status == .blocked && !decided.contains($0.stageID) }
            .map(\.stageID)
        let status: XcircuiteAgentLoopSnapshot.ApprovalState.Status
        if !rejected.isEmpty {
            status = .rejected
        } else if !pending.isEmpty {
            status = .pending
        } else if !approved.isEmpty {
            status = .approved
        } else {
            status = .notRequired
        }
        return XcircuiteAgentLoopSnapshot.ApprovalState(
            status: status,
            pendingStageIDs: stableUnique(pending),
            approvedStageIDs: stableUnique(approved),
            rejectedStageIDs: stableUnique(rejected)
        )
    }

    private func resumeReadiness(
        runStatus: XcircuiteRunStatus,
        evidenceCoverage: XcircuiteAgentLoopSnapshot.EvidenceCoverage,
        budgetUsage: XcircuiteAgentLoopSnapshot.BudgetUsage,
        approvalState: XcircuiteAgentLoopSnapshot.ApprovalState
    ) -> XcircuiteAgentLoopSnapshot.ResumeReadiness {
        var reasons: [String] = []
        if runStatus == .cancelled {
            return XcircuiteAgentLoopSnapshot.ResumeReadiness(
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
            return XcircuiteAgentLoopSnapshot.ResumeReadiness(status: .blocked, reasons: reasons)
        }
        if !reasons.isEmpty {
            return XcircuiteAgentLoopSnapshot.ResumeReadiness(status: .needsHumanReview, reasons: reasons)
        }
        return XcircuiteAgentLoopSnapshot.ResumeReadiness(status: .ready)
    }

    private func evaluationDelta(
        envelopes: [XcircuiteArtifactEnvelope],
        outputArtifactIDs: Set<String>,
        actions: [XcircuiteRunActionRecord]
    ) -> XcircuiteLoopIterationSummary.EvaluationDelta {
        let scopedEnvelopes = envelopes.filter { envelope in
            outputArtifactIDs.contains(envelope.artifactID)
                || outputArtifactIDs.contains(envelope.reference.artifactID ?? "")
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
        return XcircuiteLoopIterationSummary.EvaluationDelta(
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
        _ actions: [XcircuiteRunActionRecord]
    ) -> [XcircuiteLoopIterationSummary.RiskSignal] {
        actions.flatMap { action in
            action.diagnostics.enumerated().compactMap { index, diagnostic in
                let severity = guardSeverity(diagnostic.severity)
                guard severity >= .warning else {
                    return nil
                }
                return XcircuiteLoopIterationSummary.RiskSignal(
                    signalID: "\(action.actionID)-diagnostic-\(index)",
                    detectorID: "actionDiagnostic",
                    severity: severity,
                    reason: diagnostic.message,
                    actionIDs: [action.actionID],
                    artifactIDs: action.outputs.compactMap(\.artifactID),
                    metadata: ["diagnosticCode": .string(diagnostic.code)]
                )
            }
        }
    }

    private func iterationStatus(_ statuses: [XcircuiteRunActionStatus]) -> XcircuiteLoopIterationSummary.Status {
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

    private func allDiagnostics(from ledger: FlowRunLedger) -> [XcircuiteRunActionDiagnostic] {
        var diagnostics = ledger.actions.flatMap(\.diagnostics)
        diagnostics.append(contentsOf: ledger.stages.flatMap(\.diagnostics).map(runActionDiagnostic))
        diagnostics.append(contentsOf: ledger.stages.flatMap(\.gates).flatMap(\.diagnostics).map(runActionDiagnostic))
        return diagnostics
    }

    private func runActionDiagnostic(_ diagnostic: FlowDiagnostic) -> XcircuiteRunActionDiagnostic {
        XcircuiteRunActionDiagnostic(
            severity: runActionSeverity(diagnostic.severity),
            code: diagnostic.code,
            message: diagnostic.message
        )
    }

    private func runActionSeverity(_ severity: FlowDiagnosticSeverity) -> XcircuiteRunActionDiagnosticSeverity {
        switch severity {
        case .info:
            .info
        case .warning:
            .warning
        case .error:
            .error
        }
    }

    private func guardSeverity(_ severity: XcircuiteRunActionDiagnosticSeverity) -> XcircuiteRunGuardSeverity {
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
        status: XcircuiteEvaluationStatus,
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

    private func elapsedSeconds(from actions: [XcircuiteRunActionRecord]) -> Int? {
        guard let first = actions.map(\.createdAt).min(),
              let last = actions.map(\.createdAt).max() else {
            return nil
        }
        return max(0, Int(last.timeIntervalSince(first)))
    }

    private func isStale(
        _ reference: XcircuiteFileReference,
        maximumAgeSeconds: Int,
        generatedAt: Date,
        projectRoot: URL
    ) -> Bool {
        let url = projectRoot.appending(path: reference.path)
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path(percentEncoded: false)
            )
            guard let modifiedAt = attributes[.modificationDate] as? Date else {
                return true
            }
            return generatedAt.timeIntervalSince(modifiedAt) > Double(maximumAgeSeconds)
        } catch {
            return true
        }
    }

    private func stableUniqueReferences(_ references: [XcircuiteFileReference]) -> [XcircuiteFileReference] {
        var seen: Set<String> = []
        var result: [XcircuiteFileReference] = []
        for reference in references {
            let key = reference.artifactID ?? reference.path
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(reference)
        }
        return result.sorted { left, right in
            (left.artifactID ?? left.path) < (right.artifactID ?? right.path)
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

    private func stringMetadata(_ key: String, in metadata: [String: XcircuiteJSONValue]) -> String? {
        guard case .string(let value)? = metadata[key], !value.isEmpty else {
            return nil
        }
        return value
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }
}

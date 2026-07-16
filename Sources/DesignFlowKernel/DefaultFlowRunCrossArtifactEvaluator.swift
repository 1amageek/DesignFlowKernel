import CircuiteFoundation
import Foundation

public struct DefaultFlowRunCrossArtifactEvaluator: Sendable {
    private let loader: any FlowRunLedgerLoading
    private let evidencePersistence: any FlowRunEvidencePersisting

    public init(
        loader: any FlowRunLedgerLoading,
        evidencePersistence: any FlowRunEvidencePersisting
    ) {
        self.loader = loader
        self.evidencePersistence = evidencePersistence
    }

    public func compareArtifacts(
        runID: String,
        projectRoot: URL,
        profile: FlowEvaluationProfile? = nil,
        generatedAt: Date = Date(),
        persist: Bool = true
    ) async throws -> FlowRunCrossArtifactEvaluationResult {
        let ledger = try await loader.loadRunLedger(runID: runID)
        let envelopes = try await evidencePersistence
            .loadArtifactEnvelopeRecords(runID: runID)
            .map(\.envelope)
        let artifactReferences = try availableArtifactReferences(from: ledger, envelopes: envelopes)
        let channelResults = buildChannelResults(
            ledger: ledger,
            envelopes: envelopes,
            artifactReferences: artifactReferences,
            profile: profile
        )
        let diagnostics = buildDiagnostics(
            ledger: ledger,
            envelopes: envelopes,
            channelResults: channelResults,
            profile: profile
        )
        let evaluation = FlowCrossArtifactEvaluation(
            evaluationID: "cross-artifact-evaluation-\(ledger.runID)",
            runID: ledger.runID,
            profileID: profile?.profileID,
            status: overallStatus(from: channelResults),
            generatedAt: generatedAt,
            artifactIDs: stableUnique(artifactReferences.map { $0.id.rawValue } + envelopes.map(\.artifactID)),
            channelResults: channelResults,
            diagnostics: diagnostics,
            summary: summary(from: channelResults, diagnostics: diagnostics)
        )

        var producedReferences: [ArtifactReference] = []
        if persist {
            let reference = try await evidencePersistence.persistCrossArtifactEvaluation(
                evaluation
            )
            producedReferences.append(reference)
        }

        return FlowRunCrossArtifactEvaluationResult(
            runID: ledger.runID,
            evaluation: evaluation,
            artifactReferences: producedReferences
        )
    }

    private func buildChannelResults(
        ledger: FlowRunLedger,
        envelopes: [FlowArtifactEnvelope],
        artifactReferences: [ArtifactReference],
        profile: FlowEvaluationProfile?
    ) -> [FlowEvaluationChannelResult] {
        var results: [FlowEvaluationChannelResult] = []
        results.append(contentsOf: stageChannelResults(from: ledger))
        results.append(contentsOf: artifactEnvelopeChannelResults(from: envelopes))
        if let designDiff = ledger.designDiff {
            results.append(contentsOf: designDiffChannelResults(from: designDiff))
        }
        if let profile {
            results.append(contentsOf: profileCoverageChannelResults(
                profile: profile,
                envelopes: envelopes,
                artifactReferences: artifactReferences,
                existingResults: results
            ))
        }
        return stableUniqueChannelResults(results)
    }

    private func stageChannelResults(from ledger: FlowRunLedger) -> [FlowEvaluationChannelResult] {
        ledger.stages.flatMap { stage in
            var results = [
                FlowEvaluationChannelResult(
                    channelID: "stage.\(stage.stageID).status",
                    status: evaluationStatus(from: stage.status),
                    observedValue: .text(stage.status.rawValue),
                    diagnostics: stage.diagnostics.map(runActionDiagnostic),
                    context: FlowEvaluationContext(stageID: stage.stageID, source: "stage-result")
                ),
            ]
            results.append(contentsOf: stage.gates.map { gate in
                FlowEvaluationChannelResult(
                    channelID: "stage.\(stage.stageID).gate.\(gate.gateID)",
                    status: evaluationStatus(from: gate.status),
                    observedValue: .text(gate.status.rawValue),
                    diagnostics: gate.diagnostics.map(runActionDiagnostic),
                    context: FlowEvaluationContext(
                        stageID: stage.stageID,
                        gateID: gate.gateID,
                        source: "stage-gate"
                    )
                )
            })
            return results
        }
    }

    private func artifactEnvelopeChannelResults(
        from envelopes: [FlowArtifactEnvelope]
    ) -> [FlowEvaluationChannelResult] {
        envelopes.flatMap { envelope in
            var results: [FlowEvaluationChannelResult] = []
            if let evaluationResult = envelope.evaluationResult {
                results.append(
                    FlowEvaluationChannelResult(
                        channelID: "artifact.\(envelope.artifactID).status",
                        status: evaluationResult.status,
                        observedValue: .text(evaluationResult.status.rawValue),
                        diagnostics: evaluationResult.feedbackSignals.map(feedbackDiagnostic),
                        context: FlowEvaluationContext(
                            artifactID: envelope.artifactID,
                            artifactRole: envelope.role,
                            source: "artifact-evaluation"
                        )
                    )
                )
                results.append(contentsOf: evaluationResult.channelResults.map { channel in
                    var updated = channel
                    updated.context = merging(
                        channel.context,
                        artifactID: envelope.artifactID,
                        artifactRole: envelope.role,
                        source: "artifact-evaluation-channel"
                    )
                    return updated
                })
            }
            if let observationSet = envelope.observationSet {
                results.append(contentsOf: observationSet.channels.map { channel in
                    FlowEvaluationChannelResult(
                        channelID: "observation.\(channel.channelID).availability",
                        status: evaluationStatus(from: channel.status),
                        observedValue: channel.value ?? .text(channel.status.rawValue),
                        confidence: channel.confidence,
                        context: FlowEvaluationContext(
                            artifactID: envelope.artifactID,
                            artifactRole: envelope.role,
                            observationChannelID: channel.channelID,
                            observationStatus: channel.status,
                            source: "observation-set"
                        )
                    )
                })
            }
            if envelope.evaluationResult == nil && envelope.observationSet == nil {
                results.append(
                    FlowEvaluationChannelResult(
                        channelID: "artifact.\(envelope.artifactID).evidence",
                        status: .inconclusive,
                        observedValue: .text("present_without_structured_evaluation"),
                        context: FlowEvaluationContext(
                            artifactID: envelope.artifactID,
                            artifactRole: envelope.role,
                            source: "artifact-envelope"
                        )
                    )
                )
            }
            return results
        }
    }

    private func designDiffChannelResults(
        from designDiff: DesignDiff
    ) -> [FlowEvaluationChannelResult] {
        [
            FlowEvaluationChannelResult(
                channelID: "designDiff.reviewState",
                status: evaluationStatus(from: designDiff.reviewState),
                observedValue: .text(designDiff.reviewState.rawValue),
                context: FlowEvaluationContext(source: "design-diff")
            ),
            FlowEvaluationChannelResult(
                channelID: "designDiff.changeCount",
                status: designDiff.changes.isEmpty ? .inconclusive : evaluationStatus(from: designDiff.reviewState),
                observedValue: .scalar(Double(designDiff.changes.count)),
                context: FlowEvaluationContext(source: "design-diff")
            ),
        ]
    }

    private func profileCoverageChannelResults(
        profile: FlowEvaluationProfile,
        envelopes: [FlowArtifactEnvelope],
        artifactReferences: [ArtifactReference],
        existingResults: [FlowEvaluationChannelResult]
    ) -> [FlowEvaluationChannelResult] {
        let artifactRoles = Set(
            envelopes.map(\.role) + artifactReferences.map { $0.locator.role.rawValue }
        )
        let resultChannelIDs = Set(existingResults.map(\.channelID))
        let observedChannelIDs = Set(envelopes.flatMap { envelope in
            (envelope.evaluationResult?.channelResults.map(\.channelID) ?? [])
                + (envelope.observationSet?.channels.map(\.channelID) ?? [])
        })
        var results: [FlowEvaluationChannelResult] = []

        for role in profile.artifactRoles where role.required && !artifactRoles.contains(role.role) {
            results.append(
                FlowEvaluationChannelResult(
                    criterionID: role.role,
                    channelID: "artifactRole.\(role.role).coverage",
                    status: .needsHumanReview,
                    observedValue: .text("missing"),
                    diagnostics: [
                        FlowRunDiagnostic(
                            severity: .warning,
                            code: "missing-required-artifact-role",
                            message: "Required artifact role '\(role.role)' is not present in this run."
                        ),
                    ],
                    context: FlowEvaluationContext(
                        artifactRole: role.role,
                        profileID: profile.profileID
                    )
                )
            )
        }

        for analysis in profile.requiredAnalyses where analysis.required {
            let present = artifactRoles.contains(analysis.artifactRole)
                || resultChannelIDs.contains("requiredAnalysis.\(analysis.analysisID).coverage")
            if !present {
                results.append(
                    FlowEvaluationChannelResult(
                        criterionID: analysis.analysisID,
                        channelID: "requiredAnalysis.\(analysis.analysisID).coverage",
                        status: .needsHumanReview,
                        observedValue: .text("missing"),
                        diagnostics: [
                            FlowRunDiagnostic(
                                severity: .warning,
                                code: "missing-required-analysis",
                                message: "Required analysis '\(analysis.analysisID)' did not produce artifact role '\(analysis.artifactRole)'."
                            ),
                        ],
                        context: FlowEvaluationContext(
                            artifactRole: analysis.artifactRole,
                            profileID: profile.profileID,
                            domain: analysis.domain
                        )
                    )
                )
            }
        }

        for metric in profile.metricChannels where metric.required && !observedChannelIDs.contains(metric.channelID) {
            results.append(
                FlowEvaluationChannelResult(
                    criterionID: metric.channelID,
                    channelID: "metric.\(metric.channelID).coverage",
                    status: .inconclusive,
                    observedValue: .text("missing"),
                    diagnostics: [
                        FlowRunDiagnostic(
                            severity: .warning,
                            code: "missing-required-metric-channel",
                            message: "Required metric channel '\(metric.channelID)' is not present in artifact evaluations or observations."
                        ),
                    ],
                    context: FlowEvaluationContext(
                        profileID: profile.profileID,
                        metricChannelID: metric.channelID
                    )
                )
            )
        }

        return results
    }

    private func buildDiagnostics(
        ledger: FlowRunLedger,
        envelopes: [FlowArtifactEnvelope],
        channelResults: [FlowEvaluationChannelResult],
        profile: FlowEvaluationProfile?
    ) -> [FlowRunDiagnostic] {
        var diagnostics = ledger.actions.flatMap(\.diagnostics)
        diagnostics.append(contentsOf: ledger.stages.flatMap(\.diagnostics).map(runActionDiagnostic))
        diagnostics.append(contentsOf: ledger.stages.flatMap(\.gates).flatMap(\.diagnostics).map(runActionDiagnostic))
        diagnostics.append(contentsOf: envelopes.compactMap(\.evaluationResult).flatMap(\.feedbackSignals).map(feedbackDiagnostic))
        diagnostics.append(contentsOf: channelResults.flatMap(\.diagnostics))

        if envelopes.isEmpty {
            diagnostics.append(
                FlowRunDiagnostic(
                    severity: .warning,
                    code: "no-artifact-envelopes",
                    message: "No artifact envelopes were found; cross-artifact evaluation is limited to ledger status."
                )
            )
        }
        if profile != nil && channelResults.contains(where: { $0.status == .needsHumanReview || $0.status == .inconclusive }) {
            diagnostics.append(
                FlowRunDiagnostic(
                    severity: .warning,
                    code: "profile-coverage-incomplete",
                    message: "The evaluation profile has required analysis, artifact, or metric coverage that is not fully satisfied."
                )
            )
        }
        return stableUniqueDiagnostics(diagnostics)
    }

    private func availableArtifactReferences(
        from ledger: FlowRunLedger,
        envelopes: [FlowArtifactEnvelope]
    ) throws -> [ArtifactReference] {
        stableUniqueReferences(
            ledger.runManifest.artifacts
                + ledger.stages.flatMap(\.artifacts)
                + envelopes.map(\.reference)
        )
    }

    private func overallStatus(
        from results: [FlowEvaluationChannelResult]
    ) -> FlowEvaluationStatus {
        guard !results.isEmpty else {
            return .inconclusive
        }
        if results.contains(where: { $0.status == .blocked }) {
            return .blocked
        }
        if results.contains(where: { $0.status == .rejected }) {
            return .rejected
        }
        if results.contains(where: { $0.status == .needsHumanReview }) {
            return .needsHumanReview
        }
        if results.contains(where: { $0.status == .inconclusive }) {
            return .inconclusive
        }
        return .accepted
    }

    private func evaluationStatus(
        from status: FlowStageStatus
    ) -> FlowEvaluationStatus {
        switch status {
        case .succeeded:
            .accepted
        case .failed:
            .rejected
        case .blocked:
            .blocked
        case .pending, .running, .skipped:
            .inconclusive
        }
    }

    private func evaluationStatus(
        from status: FlowGateStatus
    ) -> FlowEvaluationStatus {
        switch status {
        case .passed, .waived:
            .accepted
        case .failed:
            .rejected
        case .incomplete:
            .needsHumanReview
        case .blocked:
            .blocked
        }
    }

    private func evaluationStatus(
        from status: FlowObservationChannelStatus
    ) -> FlowEvaluationStatus {
        switch status {
        case .observed, .derived:
            .accepted
        case .missing:
            .needsHumanReview
        case .uncalibrated:
            .inconclusive
        case .failed:
            .rejected
        }
    }

    private func evaluationStatus(
        from state: DesignDiffReviewState
    ) -> FlowEvaluationStatus {
        switch state {
        case .proposed:
            .needsHumanReview
        case .approved, .applied:
            .accepted
        case .rejected:
            .rejected
        case .superseded:
            .inconclusive
        }
    }

    private func summary(
        from results: [FlowEvaluationChannelResult],
        diagnostics: [FlowRunDiagnostic]
    ) -> String {
        let counts = Dictionary(grouping: results, by: \.status)
            .mapValues(\.count)
        let accepted = counts[.accepted, default: 0]
        let rejected = counts[.rejected, default: 0]
        let needsReview = counts[.needsHumanReview, default: 0]
        let blocked = counts[.blocked, default: 0]
        let inconclusive = counts[.inconclusive, default: 0]
        let errorCount = diagnostics.filter { $0.severity == .error }.count
        return "accepted=\(accepted), rejected=\(rejected), needsHumanReview=\(needsReview), blocked=\(blocked), inconclusive=\(inconclusive), errorDiagnostics=\(errorCount)"
    }

    private func feedbackDiagnostic(
        _ signal: FlowFeedbackSignal
    ) -> FlowRunDiagnostic {
        FlowRunDiagnostic(
            severity: runActionSeverity(signal.severity),
            code: signal.signalID,
            message: signal.summary
        )
    }

    private func runActionSeverity(_ severity: FlowFeedbackSeverity) -> FlowRunDiagnosticSeverity {
        switch severity {
        case .info:
            .info
        case .warning:
            .warning
        case .error, .blocker:
            .error
        }
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

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            unique.append(value)
        }
        return unique
    }

    private func stableUniqueReferences(
        _ references: [ArtifactReference]
    ) -> [ArtifactReference] {
        var seen: Set<String> = []
        var unique: [ArtifactReference] = []
        for reference in references {
            let key = reference.id.rawValue
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            unique.append(reference)
        }
        return unique
    }

    private func stableUniqueChannelResults(
        _ results: [FlowEvaluationChannelResult]
    ) -> [FlowEvaluationChannelResult] {
        var seen: Set<String> = []
        var unique: [FlowEvaluationChannelResult] = []
        for result in results {
            let key = [
                result.criterionID ?? "",
                result.channelID,
                result.context?.artifactID ?? "",
                result.context?.stageID ?? "",
            ].joined(separator: "|")
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            unique.append(result)
        }
        return unique
    }

    private func stableUniqueDiagnostics(
        _ diagnostics: [FlowRunDiagnostic]
    ) -> [FlowRunDiagnostic] {
        var seen: Set<String> = []
        var unique: [FlowRunDiagnostic] = []
        for diagnostic in diagnostics {
            let key = "\(diagnostic.severity.rawValue)|\(diagnostic.code)|\(diagnostic.message)"
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            unique.append(diagnostic)
        }
        return unique
    }

    private func merging(
        _ existing: FlowEvaluationContext?,
        artifactID: String,
        artifactRole: String,
        source: String
    ) -> FlowEvaluationContext {
        var context = existing ?? FlowEvaluationContext()
        context.artifactID = artifactID
        context.artifactRole = artifactRole
        context.source = source
        return context
    }

}

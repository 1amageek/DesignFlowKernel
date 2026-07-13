import Foundation

public struct DefaultFlowRunCrossArtifactEvaluator: Sendable {
    private let loader: any FlowRunLedgerLoading
    private let packageStore: XcircuitePackageStore

    public init(
        loader: any FlowRunLedgerLoading = FlowRunLedgerLoader(),
        packageStore: XcircuitePackageStore = XcircuitePackageStore()
    ) {
        self.loader = loader
        self.packageStore = packageStore
    }

    public func compareArtifacts(
        runID: String,
        projectRoot: URL,
        profile: XcircuiteEvaluationProfile? = nil,
        generatedAt: Date = Date(),
        persist: Bool = true
    ) throws -> FlowRunCrossArtifactEvaluationResult {
        let ledger = try loader.loadRunLedger(runID: runID, projectRoot: projectRoot)
        let envelopes = try loadArtifactEnvelopes(from: ledger)
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
        let evaluation = XcircuiteCrossArtifactEvaluation(
            evaluationID: "cross-artifact-evaluation-\(ledger.runID)",
            runID: ledger.runID,
            profileID: profile?.profileID,
            status: overallStatus(from: channelResults),
            generatedAt: generatedAt,
            artifactIDs: stableUnique(artifactReferences.compactMap(\.artifactID) + envelopes.map(\.artifactID)),
            channelResults: channelResults,
            diagnostics: diagnostics,
            summary: summary(from: channelResults, diagnostics: diagnostics),
            metadata: [
                "stageCount": .number(Double(ledger.stages.count)),
                "artifactEnvelopeCount": .number(Double(envelopes.count)),
                "artifactReferenceCount": .number(Double(artifactReferences.count)),
                "designChangeCount": .number(Double(ledger.designDiff?.changes.count ?? 0)),
            ]
        )

        var producedReferences: [XcircuiteFileReference] = []
        if persist {
            producedReferences.append(
                try packageStore.writeCrossArtifactEvaluation(
                    evaluation,
                    inProjectAt: projectRoot
                )
            )
        }

        return FlowRunCrossArtifactEvaluationResult(
            runID: ledger.runID,
            evaluation: evaluation,
            artifactReferences: producedReferences
        )
    }

    private func buildChannelResults(
        ledger: FlowRunLedger,
        envelopes: [XcircuiteArtifactEnvelope],
        artifactReferences: [XcircuiteFileReference],
        profile: XcircuiteEvaluationProfile?
    ) -> [XcircuiteEvaluationChannelResult] {
        var results: [XcircuiteEvaluationChannelResult] = []
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

    private func stageChannelResults(from ledger: FlowRunLedger) -> [XcircuiteEvaluationChannelResult] {
        ledger.stages.flatMap { stage in
            var results = [
                XcircuiteEvaluationChannelResult(
                    channelID: "stage.\(stage.stageID).status",
                    status: evaluationStatus(from: stage.status),
                    observedValue: .string(stage.status.rawValue),
                    diagnostics: stage.diagnostics.map(runActionDiagnostic),
                    metadata: [
                        "stageID": .string(stage.stageID),
                        "source": .string("stage-result"),
                    ]
                ),
            ]
            results.append(contentsOf: stage.gates.map { gate in
                XcircuiteEvaluationChannelResult(
                    channelID: "stage.\(stage.stageID).gate.\(gate.gateID)",
                    status: evaluationStatus(from: gate.status),
                    observedValue: .string(gate.status.rawValue),
                    diagnostics: gate.diagnostics.map(runActionDiagnostic),
                    metadata: [
                        "stageID": .string(stage.stageID),
                        "gateID": .string(gate.gateID),
                        "source": .string("stage-gate"),
                    ]
                )
            })
            return results
        }
    }

    private func artifactEnvelopeChannelResults(
        from envelopes: [XcircuiteArtifactEnvelope]
    ) -> [XcircuiteEvaluationChannelResult] {
        envelopes.flatMap { envelope in
            var results: [XcircuiteEvaluationChannelResult] = []
            if let evaluationResult = envelope.evaluationResult {
                results.append(
                    XcircuiteEvaluationChannelResult(
                        channelID: "artifact.\(envelope.artifactID).status",
                        status: evaluationResult.status,
                        observedValue: .string(evaluationResult.status.rawValue),
                        diagnostics: evaluationResult.feedbackSignals.map(feedbackDiagnostic),
                        metadata: [
                            "artifactID": .string(envelope.artifactID),
                            "artifactRole": .string(envelope.role),
                            "source": .string("artifact-evaluation"),
                        ]
                    )
                )
                results.append(contentsOf: evaluationResult.channelResults.map { channel in
                    var updated = channel
                    updated.metadata = mergeMetadata(
                        channel.metadata,
                        [
                            "artifactID": .string(envelope.artifactID),
                            "artifactRole": .string(envelope.role),
                            "source": .string("artifact-evaluation-channel"),
                        ]
                    )
                    return updated
                })
            }
            if let observationSet = envelope.observationSet {
                results.append(contentsOf: observationSet.channels.map { channel in
                    XcircuiteEvaluationChannelResult(
                        channelID: "observation.\(channel.channelID).availability",
                        status: evaluationStatus(from: channel.status),
                        observedValue: channel.value ?? .string(channel.status.rawValue),
                        confidence: channel.confidence,
                        metadata: [
                            "artifactID": .string(envelope.artifactID),
                            "artifactRole": .string(envelope.role),
                            "observationChannelID": .string(channel.channelID),
                            "observationStatus": .string(channel.status.rawValue),
                            "source": .string("observation-set"),
                        ]
                    )
                })
            }
            if envelope.evaluationResult == nil && envelope.observationSet == nil {
                results.append(
                    XcircuiteEvaluationChannelResult(
                        channelID: "artifact.\(envelope.artifactID).evidence",
                        status: .inconclusive,
                        observedValue: .string("present_without_structured_evaluation"),
                        metadata: [
                            "artifactID": .string(envelope.artifactID),
                            "artifactRole": .string(envelope.role),
                            "source": .string("artifact-envelope"),
                        ]
                    )
                )
            }
            return results
        }
    }

    private func designDiffChannelResults(
        from designDiff: XcircuiteDesignDiff
    ) -> [XcircuiteEvaluationChannelResult] {
        [
            XcircuiteEvaluationChannelResult(
                channelID: "designDiff.reviewState",
                status: evaluationStatus(from: designDiff.reviewState),
                observedValue: .string(designDiff.reviewState.rawValue),
                metadata: [
                    "source": .string("design-diff"),
                ]
            ),
            XcircuiteEvaluationChannelResult(
                channelID: "designDiff.changeCount",
                status: designDiff.changes.isEmpty ? .inconclusive : evaluationStatus(from: designDiff.reviewState),
                observedValue: .number(Double(designDiff.changes.count)),
                metadata: [
                    "source": .string("design-diff"),
                ]
            ),
        ]
    }

    private func profileCoverageChannelResults(
        profile: XcircuiteEvaluationProfile,
        envelopes: [XcircuiteArtifactEnvelope],
        artifactReferences: [XcircuiteFileReference],
        existingResults: [XcircuiteEvaluationChannelResult]
    ) -> [XcircuiteEvaluationChannelResult] {
        let artifactRoles = Set(envelopes.map(\.role) + artifactReferences.compactMap(\.artifactID))
        let resultChannelIDs = Set(existingResults.map(\.channelID))
        let observedChannelIDs = Set(envelopes.flatMap { envelope in
            (envelope.evaluationResult?.channelResults.map(\.channelID) ?? [])
                + (envelope.observationSet?.channels.map(\.channelID) ?? [])
        })
        var results: [XcircuiteEvaluationChannelResult] = []

        for role in profile.artifactRoles where role.required && !artifactRoles.contains(role.role) {
            results.append(
                XcircuiteEvaluationChannelResult(
                    criterionID: role.role,
                    channelID: "artifactRole.\(role.role).coverage",
                    status: .needsHumanReview,
                    observedValue: .string("missing"),
                    diagnostics: [
                        XcircuiteRunActionDiagnostic(
                            severity: .warning,
                            code: "missing-required-artifact-role",
                            message: "Required artifact role '\(role.role)' is not present in this run."
                        ),
                    ],
                    metadata: [
                        "profileID": .string(profile.profileID),
                        "artifactRole": .string(role.role),
                    ]
                )
            )
        }

        for analysis in profile.requiredAnalyses where analysis.required {
            let present = artifactRoles.contains(analysis.artifactRole)
                || resultChannelIDs.contains("requiredAnalysis.\(analysis.analysisID).coverage")
            if !present {
                results.append(
                    XcircuiteEvaluationChannelResult(
                        criterionID: analysis.analysisID,
                        channelID: "requiredAnalysis.\(analysis.analysisID).coverage",
                        status: .needsHumanReview,
                        observedValue: .string("missing"),
                        diagnostics: [
                            XcircuiteRunActionDiagnostic(
                                severity: .warning,
                                code: "missing-required-analysis",
                                message: "Required analysis '\(analysis.analysisID)' did not produce artifact role '\(analysis.artifactRole)'."
                            ),
                        ],
                        metadata: [
                            "profileID": .string(profile.profileID),
                            "domain": .string(analysis.domain),
                            "artifactRole": .string(analysis.artifactRole),
                        ]
                    )
                )
            }
        }

        for metric in profile.metricChannels where metric.required && !observedChannelIDs.contains(metric.channelID) {
            results.append(
                XcircuiteEvaluationChannelResult(
                    criterionID: metric.channelID,
                    channelID: "metric.\(metric.channelID).coverage",
                    status: .inconclusive,
                    observedValue: .string("missing"),
                    diagnostics: [
                        XcircuiteRunActionDiagnostic(
                            severity: .warning,
                            code: "missing-required-metric-channel",
                            message: "Required metric channel '\(metric.channelID)' is not present in artifact evaluations or observations."
                        ),
                    ],
                    metadata: [
                        "profileID": .string(profile.profileID),
                        "metricChannelID": .string(metric.channelID),
                    ]
                )
            )
        }

        return results
    }

    private func buildDiagnostics(
        ledger: FlowRunLedger,
        envelopes: [XcircuiteArtifactEnvelope],
        channelResults: [XcircuiteEvaluationChannelResult],
        profile: XcircuiteEvaluationProfile?
    ) -> [XcircuiteRunActionDiagnostic] {
        var diagnostics = ledger.actions.flatMap(\.diagnostics)
        diagnostics.append(contentsOf: ledger.stages.flatMap(\.diagnostics).map(runActionDiagnostic))
        diagnostics.append(contentsOf: ledger.stages.flatMap(\.gates).flatMap(\.diagnostics).map(runActionDiagnostic))
        diagnostics.append(contentsOf: envelopes.compactMap(\.evaluationResult).flatMap(\.feedbackSignals).map(feedbackDiagnostic))
        diagnostics.append(contentsOf: channelResults.flatMap(\.diagnostics))

        if envelopes.isEmpty {
            diagnostics.append(
                XcircuiteRunActionDiagnostic(
                    severity: .warning,
                    code: "no-artifact-envelopes",
                    message: "No artifact envelopes were found; cross-artifact evaluation is limited to ledger status."
                )
            )
        }
        if profile != nil && channelResults.contains(where: { $0.status == .needsHumanReview || $0.status == .inconclusive }) {
            diagnostics.append(
                XcircuiteRunActionDiagnostic(
                    severity: .warning,
                    code: "profile-coverage-incomplete",
                    message: "The evaluation profile has required analysis, artifact, or metric coverage that is not fully satisfied."
                )
            )
        }
        return stableUniqueDiagnostics(diagnostics)
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
    ) throws -> [XcircuiteFileReference] {
        stableUniqueReferences(
            ledger.runManifest.artifacts
                + (try ledger.stages.flatMap(\.artifacts).map { try $0.legacyXcircuiteReference() })
                + envelopes.map(\.reference)
        )
    }

    private func overallStatus(
        from results: [XcircuiteEvaluationChannelResult]
    ) -> XcircuiteEvaluationStatus {
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
    ) -> XcircuiteEvaluationStatus {
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
    ) -> XcircuiteEvaluationStatus {
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
        from status: XcircuiteObservationChannelStatus
    ) -> XcircuiteEvaluationStatus {
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
        from state: XcircuiteDesignDiffReviewState
    ) -> XcircuiteEvaluationStatus {
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
        from results: [XcircuiteEvaluationChannelResult],
        diagnostics: [XcircuiteRunActionDiagnostic]
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
        _ signal: XcircuiteFeedbackSignal
    ) -> XcircuiteRunActionDiagnostic {
        XcircuiteRunActionDiagnostic(
            severity: runActionSeverity(signal.severity),
            code: signal.signalID,
            message: signal.summary
        )
    }

    private func runActionSeverity(_ severity: XcircuiteFeedbackSeverity) -> XcircuiteRunActionDiagnosticSeverity {
        switch severity {
        case .info:
            .info
        case .warning:
            .warning
        case .error, .blocker:
            .error
        }
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
        _ references: [XcircuiteFileReference]
    ) -> [XcircuiteFileReference] {
        var seen: Set<String> = []
        var unique: [XcircuiteFileReference] = []
        for reference in references {
            let key = reference.artifactID ?? reference.path
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            unique.append(reference)
        }
        return unique
    }

    private func stableUniqueChannelResults(
        _ results: [XcircuiteEvaluationChannelResult]
    ) -> [XcircuiteEvaluationChannelResult] {
        var seen: Set<String> = []
        var unique: [XcircuiteEvaluationChannelResult] = []
        for result in results {
            let key = [
                result.criterionID ?? "",
                result.channelID,
                result.metadata["artifactID"].map(jsonKey) ?? "",
                result.metadata["stageID"].map(jsonKey) ?? "",
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
        _ diagnostics: [XcircuiteRunActionDiagnostic]
    ) -> [XcircuiteRunActionDiagnostic] {
        var seen: Set<String> = []
        var unique: [XcircuiteRunActionDiagnostic] = []
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

    private func jsonKey(_ value: XcircuiteJSONValue) -> String {
        switch value {
        case .null:
            "null"
        case .bool(let raw):
            raw ? "true" : "false"
        case .number(let raw):
            String(raw)
        case .string(let raw):
            raw
        case .array(let raw):
            raw.map(jsonKey).joined(separator: ",")
        case .object(let raw):
            raw.keys.sorted().map { "\($0)=\(jsonKey(raw[$0] ?? .null))" }.joined(separator: ",")
        }
    }

    private func mergeMetadata(
        _ left: [String: XcircuiteJSONValue],
        _ right: [String: XcircuiteJSONValue]
    ) -> [String: XcircuiteJSONValue] {
        var merged = left
        for (key, value) in right {
            merged[key] = value
        }
        return merged
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

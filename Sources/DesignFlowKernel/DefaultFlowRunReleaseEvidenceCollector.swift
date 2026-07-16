import CircuiteFoundation
import Foundation

public struct DefaultFlowRunReleaseEvidenceCollector: FlowRunReleaseEvidenceCollecting {
    public static let corpusHistoryArtifactID = "qualification-corpus-history"
    public static let performanceEnvelopeArtifactID = "qualification-performance-envelope"
    public static let contractAuditArtifactID = "qualification-contract-audit"

    private let persistence: any FlowArtifactPersisting
    private let currentDate: Date

    public init(
        persistence: any FlowArtifactPersisting,
        currentDate: Date = Date()
    ) {
        self.persistence = persistence
        self.currentDate = currentDate
    }

    public func collectReleaseEvidence(
        runID: String,
        workspaceID: FlowWorkspaceID,
        signoffDashboard: ArtifactReference,
        contractReport: ArtifactReference
    ) async throws -> FlowRunReleaseEvidenceCollectionResult {
        let dashboard: FlowRunSignoffDashboard = try await load(
            FlowRunSignoffDashboard.self,
            source: "signoff-dashboard",
            from: signoffDashboard,
            workspaceID: workspaceID
        )
        let contractReportDocument: FlowRunContractReport = try await load(
            FlowRunContractReport.self,
            source: "contract-report",
            from: contractReport,
            workspaceID: workspaceID
        )
        try validate(dashboard)
        try validate(contractReportDocument)

        let dashboardSHA256 = signoffDashboard.digest.hexadecimalValue
        let contractSHA256 = contractReport.digest.hexadecimalValue
        let collectedAt = ISO8601DateFormatter().string(from: currentDate)

        let corpusHistory = makeCorpusHistory(
            runID: runID,
            collectedAt: collectedAt,
            sourcePath: signoffDashboard.locator.location.value,
            sourceSHA256: dashboardSHA256,
            dashboard: dashboard
        )
        let performanceEnvelope = makePerformanceEnvelope(
            runID: runID,
            collectedAt: collectedAt,
            sourcePath: signoffDashboard.locator.location.value,
            sourceSHA256: dashboardSHA256,
            dashboard: dashboard
        )
        let contractAudit = makeContractAudit(
            runID: runID,
            collectedAt: collectedAt,
            sourcePath: contractReport.locator.location.value,
            sourceSHA256: contractSHA256,
            report: contractReportDocument
        )
        let artifacts = try await persistArtifacts(
            runID: runID,
            workspaceID: workspaceID,
            corpusHistory: corpusHistory,
            performanceEnvelope: performanceEnvelope,
            contractAudit: contractAudit
        )

        return FlowRunReleaseEvidenceCollectionResult(
            runID: runID,
            corpusHistory: corpusHistory,
            performanceEnvelope: performanceEnvelope,
            contractAudit: contractAudit,
            artifacts: artifacts,
            diagnostics: corpusHistory.diagnostics
                + performanceEnvelope.diagnostics
                + contractAudit.diagnostics
        )
    }

    private func load<T: Decodable>(
        _ type: T.Type,
        source: String,
        from reference: ArtifactReference,
        workspaceID: FlowWorkspaceID
    ) async throws -> T {
        do {
            let content = try await persistence.loadArtifactContent(
                for: reference
            )
            return try JSONDecoder().decode(type, from: content)
        } catch {
            throw FlowRunReleaseEvidenceCollectionError.sourceDecodeFailed(
                source: source,
                reason: error.localizedDescription
            )
        }
    }

    private func validate(_ dashboard: FlowRunSignoffDashboard) throws {
        guard dashboard.schemaVersion == 1 else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: "signoff-dashboard",
                fieldPath: "schemaVersion",
                expected: "1",
                actual: String(dashboard.schemaVersion)
            )
        }
        guard dashboard.history.domains != nil else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: "signoff-dashboard",
                fieldPath: "history.domains",
                expected: "array",
                actual: "missing"
            )
        }
        guard dashboard.history.failures != nil else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: "signoff-dashboard",
                fieldPath: "history.failures",
                expected: "array",
                actual: "missing"
            )
        }
        guard dashboard.history.promotion != nil else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: "signoff-dashboard",
                fieldPath: "history.promotion",
                expected: "object",
                actual: "missing"
            )
        }
    }

    private func validate(_ report: FlowRunContractReport) throws {
        guard report.schemaVersion == 1 else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: "contract-report",
                fieldPath: "schemaVersion",
                expected: "1",
                actual: String(report.schemaVersion)
            )
        }
    }

    private func makeCorpusHistory(
        runID: String,
        collectedAt: String,
        sourcePath: String,
        sourceSHA256: String,
        dashboard: FlowRunSignoffDashboard
    ) -> FlowRunReleaseCorpusHistory {
        let summaries = (dashboard.history.domains ?? []).map { domain in
            FlowRunReleaseCorpusHistory.DomainSummary(
                domain: domain.domain,
                status: domain.status,
                previousQualifiedEntryCount: domain.previousQualifiedEntryCount ?? 0,
                currentStatus: domain.current?.status,
                qualified: domain.current?.qualified,
                caseCount: domain.current?.caseCount,
                passRate: domain.current?.passRate,
                totalDurationSeconds: domain.current?.totalDurationSeconds,
                coverageTagCount: domain.current?.coverageTagCount,
                failureCount: domain.failures?.count ?? 0
            )
        }
        var diagnostics: [FlowDiagnostic] = []
        if dashboard.status != "passed" {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "release-corpus-dashboard-not-passed",
                    message: "Signoff qualification dashboard status is not passed."
                )
            )
        }
        if dashboard.history.status == "skipped" {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .warning,
                    code: "release-corpus-history-skipped",
                    message: "Signoff qualification dashboard did not evaluate retained history."
                )
            )
        }
        return FlowRunReleaseCorpusHistory(
            runID: runID,
            collectedAt: collectedAt,
            sourceDashboardPath: sourcePath,
            sourceDashboardSHA256: sourceSHA256,
            sourceRecordedAt: dashboard.history.entry?.recordedAt,
            dashboardStatus: dashboard.status,
            historyStatus: dashboard.history.status,
            previousEntryCount: dashboard.history.previousEntryCount ?? 0,
            appended: dashboard.history.appended,
            retainedSignoffSuiteStatus: dashboard.retainedSignoffSuite.status,
            domains: summaries,
            diagnostics: diagnostics
        )
    }

    private func makePerformanceEnvelope(
        runID: String,
        collectedAt: String,
        sourcePath: String,
        sourceSHA256: String,
        dashboard: FlowRunSignoffDashboard
    ) -> FlowRunReleasePerformanceEnvelope {
        let domains = (dashboard.history.domains ?? []).map { domain in
            FlowRunReleasePerformanceEnvelope.DomainEnvelope(
                domain: domain.domain,
                status: domain.status,
                currentTotalDurationSeconds: domain.current?.totalDurationSeconds,
                medianTotalDurationSeconds: domain.baseline?.medianTotalDurationSeconds,
                maxAllowedTotalDurationSeconds: domain.baseline?.maxAllowedTotalDurationSeconds,
                durationRegressionRatio: domain.durationRegressionRatio,
                currentPassRate: domain.current?.passRate,
                medianPassRate: domain.baseline?.medianPassRate,
                failureCount: domain.failures?.count ?? 0
            )
        }
        let diagnostics = dashboard.history.status == "failed"
            ? [
                FlowDiagnostic(
                    severity: .error,
                    code: "release-performance-history-failed",
                    message: "Signoff qualification history reports performance or promotion failures."
                ),
            ]
            : []
        return FlowRunReleasePerformanceEnvelope(
            runID: runID,
            collectedAt: collectedAt,
            sourceDashboardPath: sourcePath,
            sourceDashboardSHA256: sourceSHA256,
            sourceRecordedAt: dashboard.history.entry?.recordedAt,
            historyStatus: dashboard.history.status,
            maxTotalDurationRegression: dashboard.history.maxTotalDurationRegression,
            domains: domains,
            promotionStatus: dashboard.history.promotion?.status,
            promotionFailureCount: dashboard.history.promotion?.failures.count ?? 0,
            diagnostics: diagnostics
        )
    }

    private func makeContractAudit(
        runID: String,
        collectedAt: String,
        sourcePath: String,
        sourceSHA256: String,
        report: FlowRunContractReport
    ) -> FlowRunReleaseContractAudit {
        let contracts = report.contracts.map { contract in
            FlowRunReleaseContractAudit.ContractSummary(
                contractID: contract.id,
                owner: contract.owner,
                status: contract.status,
                expectedVersion: contract.expectedVersion,
                observedVersion: contract.observedVersion,
                requiredPathCount: contract.requiredPathCount,
                failureCount: contract.failures.count
            )
        }
        let diagnostics = report.status == "passed"
            ? []
            : [
                FlowDiagnostic(
                    severity: .error,
                    code: "release-contract-audit-not-passed",
                    message: "Versioned contract fixture report status is not passed."
                ),
            ]
        return FlowRunReleaseContractAudit(
            runID: runID,
            collectedAt: collectedAt,
            sourceReportPath: sourcePath,
            sourceReportSHA256: sourceSHA256,
            status: report.status,
            contractCount: report.contractCount,
            failedContractCount: report.failedContractCount,
            contracts: contracts,
            diagnostics: diagnostics
        )
    }

    private func persistArtifacts(
        runID: String,
        workspaceID: FlowWorkspaceID,
        corpusHistory: FlowRunReleaseCorpusHistory,
        performanceEnvelope: FlowRunReleasePerformanceEnvelope,
        contractAudit: FlowRunReleaseContractAudit
    ) async throws -> [ArtifactReference] {
        let artifacts: [(path: String, artifactID: String, value: any Encodable)] = [
            ("qualification/corpus-history.json", Self.corpusHistoryArtifactID, corpusHistory),
            ("qualification/performance-envelope.json", Self.performanceEnvelopeArtifactID, performanceEnvelope),
            ("qualification/contract-audit.json", Self.contractAuditArtifactID, contractAudit),
        ]
        var references: [ArtifactReference] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for artifact in artifacts {
            let reference = try await persistence.persistArtifact(
                content: encoder.encode(artifact.value),
                id: ArtifactID(rawValue: artifact.artifactID),
                locator: ArtifactLocator(
                    location: try ArtifactLocation(
                        workspaceRelativePath: "runs/\(runID)/\(artifact.path)"
                    ),
                    role: .output,
                    kind: .report,
                    format: .json
                ),
                runID: runID,
                mode: .replaceable
            )
            references.append(reference)
        }
        return references
    }
}

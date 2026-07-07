import Foundation
import XcircuitePackage

public struct DefaultFlowRunReleaseEvidenceCollector: FlowRunReleaseEvidenceCollecting {
    public static let corpusHistoryArtifactID = "qualification-corpus-history"
    public static let performanceEnvelopeArtifactID = "qualification-performance-envelope"
    public static let migrationAuditArtifactID = "qualification-migration-audit"

    private let packageStore: XcircuitePackageStore
    private let hasher: XcircuiteHasher
    private let currentDate: Date

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        hasher: XcircuiteHasher = XcircuiteHasher(),
        currentDate: Date = Date()
    ) {
        self.packageStore = packageStore
        self.hasher = hasher
        self.currentDate = currentDate
    }

    public func collectReleaseEvidence(
        runID: String,
        projectRoot: URL,
        signoffDashboardPath: URL,
        migrationReportPath: URL
    ) throws -> FlowRunReleaseEvidenceCollectionResult {
        let dashboard = try loadJSONValue(from: signoffDashboardPath)
        let migrationReport = try loadJSONValue(from: migrationReportPath)
        try validateSignoffDashboard(dashboard)
        try validateMigrationReport(migrationReport)
        let dashboardSHA256 = try hasher.sha256(fileAt: signoffDashboardPath)
        let migrationSHA256 = try hasher.sha256(fileAt: migrationReportPath)
        let collectedAt = timestamp(currentDate)

        let corpusHistory = makeCorpusHistory(
            runID: runID,
            collectedAt: collectedAt,
            sourcePath: signoffDashboardPath,
            sourceSHA256: dashboardSHA256,
            dashboard: dashboard
        )
        let performanceEnvelope = makePerformanceEnvelope(
            runID: runID,
            collectedAt: collectedAt,
            sourcePath: signoffDashboardPath,
            sourceSHA256: dashboardSHA256,
            dashboard: dashboard
        )
        let migrationAudit = makeMigrationAudit(
            runID: runID,
            collectedAt: collectedAt,
            sourcePath: migrationReportPath,
            sourceSHA256: migrationSHA256,
            report: migrationReport
        )

        let artifacts = try persistArtifacts(
            runID: runID,
            projectRoot: projectRoot,
            corpusHistory: corpusHistory,
            performanceEnvelope: performanceEnvelope,
            migrationAudit: migrationAudit
        )
        let diagnostics = corpusHistory.diagnostics
            + performanceEnvelope.diagnostics
            + migrationAudit.diagnostics
        return FlowRunReleaseEvidenceCollectionResult(
            runID: runID,
            corpusHistory: corpusHistory,
            performanceEnvelope: performanceEnvelope,
            migrationAudit: migrationAudit,
            artifacts: artifacts,
            diagnostics: diagnostics
        )
    }

    private func loadJSONValue(from url: URL) throws -> XcircuiteJSONValue {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XcircuitePackageError.readFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
        do {
            return try JSONDecoder().decode(XcircuiteJSONValue.self, from: data)
        } catch {
            throw XcircuitePackageError.decodeFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func validateSignoffDashboard(_ value: XcircuiteJSONValue) throws {
        let source = "signoff-dashboard"
        _ = try requiredObject(value, source: source, fieldPath: "$")
        try requireSchemaVersion(value, source: source)
        _ = try requiredString(at: ["status"], in: value, source: source)
        let history = try requiredObject(at: ["history"], in: value, source: source)
        let historyValue = XcircuiteJSONValue.object(history)
        _ = try requiredString(at: ["status"], in: historyValue, source: source, prefix: "history")
        _ = try requiredNumber(at: ["previousEntryCount"], in: historyValue, source: source, prefix: "history")
        _ = try requiredArray(at: ["domains"], in: historyValue, source: source, prefix: "history")
        _ = try requiredArray(at: ["failures"], in: historyValue, source: source, prefix: "history")
        let promotion = try requiredObject(at: ["promotion"], in: historyValue, source: source, prefix: "history")
        let promotionValue = XcircuiteJSONValue.object(promotion)
        _ = try requiredString(at: ["status"], in: promotionValue, source: source, prefix: "history.promotion")
        _ = try requiredArray(at: ["failures"], in: promotionValue, source: source, prefix: "history.promotion")
        let retainedSuite = try requiredObject(at: ["retainedSignoffSuite"], in: value, source: source)
        let retainedSuiteValue = XcircuiteJSONValue.object(retainedSuite)
        _ = try requiredString(at: ["status"], in: retainedSuiteValue, source: source, prefix: "retainedSignoffSuite")
    }

    private func validateMigrationReport(_ value: XcircuiteJSONValue) throws {
        let source = "migration-report"
        _ = try requiredObject(value, source: source, fieldPath: "$")
        try requireSchemaVersion(value, source: source)
        _ = try requiredString(at: ["status"], in: value, source: source)
        _ = try requiredNumber(at: ["contractCount"], in: value, source: source)
        _ = try requiredNumber(at: ["failedContractCount"], in: value, source: source)
        let contracts = try requiredArray(at: ["contracts"], in: value, source: source)
        for (index, item) in contracts.enumerated() {
            let contract = try requiredObject(
                item,
                source: source,
                fieldPath: "contracts[\(index)]"
            )
            let contractValue = XcircuiteJSONValue.object(contract)
            _ = try requiredString(at: ["id"], in: contractValue, source: source, prefix: "contracts[\(index)]")
            _ = try requiredString(at: ["owner"], in: contractValue, source: source, prefix: "contracts[\(index)]")
            _ = try requiredString(at: ["status"], in: contractValue, source: source, prefix: "contracts[\(index)]")
        }
    }

    private func requireSchemaVersion(_ value: XcircuiteJSONValue, source: String) throws {
        let schemaVersion = try requiredNumber(at: ["schemaVersion"], in: value, source: source)
        guard schemaVersion == 1 else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: source,
                fieldPath: "schemaVersion",
                expected: "1",
                actual: String(schemaVersion)
            )
        }
    }

    private func makeCorpusHistory(
        runID: String,
        collectedAt: String,
        sourcePath: URL,
        sourceSHA256: String,
        dashboard: XcircuiteJSONValue
    ) -> FlowRunReleaseCorpusHistory {
        let history = value(at: ["history"], in: dashboard)
        let sourceRecordedAt = stringValue(value(at: ["entry", "recordedAt"], in: history))
        let retainedSignoffSuite = value(at: ["retainedSignoffSuite"], in: dashboard)
        let domains = arrayValue(value(at: ["domains"], in: history)) ?? []
        let summaries = domains.compactMap { item -> FlowRunReleaseCorpusHistory.DomainSummary? in
            guard let object = objectValue(item) else {
                return nil
            }
            let current = objectValue(object["current"])
            return FlowRunReleaseCorpusHistory.DomainSummary(
                domain: stringValue(object["domain"]) ?? "",
                status: stringValue(object["status"]),
                previousQualifiedEntryCount: intValue(object["previousQualifiedEntryCount"]) ?? 0,
                currentStatus: stringValue(current?["status"]),
                qualified: boolValue(current?["qualified"]),
                caseCount: numberValue(current?["caseCount"]),
                passRate: numberValue(current?["passRate"]),
                totalDurationSeconds: numberValue(current?["totalDurationSeconds"]),
                coverageTagCount: numberValue(current?["coverageTagCount"]),
                failureCount: arrayValue(object["failures"])?.count ?? 0
            )
        }
        var diagnostics: [FlowDiagnostic] = []
        if stringValue(value(at: ["status"], in: dashboard)) != "passed" {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "release-corpus-dashboard-not-passed",
                    message: "Signoff qualification dashboard status is not passed."
                )
            )
        }
        if stringValue(value(at: ["status"], in: history)) == "skipped" {
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
            sourceDashboardPath: sourcePath.path(percentEncoded: false),
            sourceDashboardSHA256: sourceSHA256,
            sourceRecordedAt: sourceRecordedAt,
            dashboardStatus: stringValue(value(at: ["status"], in: dashboard)),
            historyStatus: stringValue(value(at: ["status"], in: history)),
            previousEntryCount: intValue(value(at: ["previousEntryCount"], in: history)) ?? 0,
            appended: boolValue(value(at: ["appended"], in: history)),
            retainedSignoffSuiteStatus: stringValue(value(at: ["status"], in: retainedSignoffSuite)),
            domains: summaries,
            diagnostics: diagnostics
        )
    }

    private func makePerformanceEnvelope(
        runID: String,
        collectedAt: String,
        sourcePath: URL,
        sourceSHA256: String,
        dashboard: XcircuiteJSONValue
    ) -> FlowRunReleasePerformanceEnvelope {
        let history = value(at: ["history"], in: dashboard)
        let sourceRecordedAt = stringValue(value(at: ["entry", "recordedAt"], in: history))
        let domains = arrayValue(value(at: ["domains"], in: history)) ?? []
        let envelopes = domains.compactMap { item -> FlowRunReleasePerformanceEnvelope.DomainEnvelope? in
            guard let object = objectValue(item) else {
                return nil
            }
            let current = objectValue(object["current"])
            let baseline = objectValue(object["baseline"])
            return FlowRunReleasePerformanceEnvelope.DomainEnvelope(
                domain: stringValue(object["domain"]) ?? "",
                status: stringValue(object["status"]),
                currentTotalDurationSeconds: numberValue(current?["totalDurationSeconds"]),
                medianTotalDurationSeconds: numberValue(baseline?["medianTotalDurationSeconds"]),
                maxAllowedTotalDurationSeconds: numberValue(baseline?["maxAllowedTotalDurationSeconds"]),
                durationRegressionRatio: numberValue(object["durationRegressionRatio"]),
                currentPassRate: numberValue(current?["passRate"]),
                medianPassRate: numberValue(baseline?["medianPassRate"]),
                failureCount: arrayValue(object["failures"])?.count ?? 0
            )
        }
        let promotion = value(at: ["promotion"], in: history)
        var diagnostics: [FlowDiagnostic] = []
        if stringValue(value(at: ["status"], in: history)) == "failed" {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "release-performance-history-failed",
                    message: "Signoff qualification history reports performance or promotion failures."
                )
            )
        }
        return FlowRunReleasePerformanceEnvelope(
            runID: runID,
            collectedAt: collectedAt,
            sourceDashboardPath: sourcePath.path(percentEncoded: false),
            sourceDashboardSHA256: sourceSHA256,
            sourceRecordedAt: sourceRecordedAt,
            historyStatus: stringValue(value(at: ["status"], in: history)),
            maxTotalDurationRegression: numberValue(value(at: ["maxTotalDurationRegression"], in: history)),
            domains: envelopes,
            promotionStatus: stringValue(value(at: ["status"], in: promotion)),
            promotionFailureCount: arrayValue(value(at: ["failures"], in: promotion))?.count ?? 0,
            diagnostics: diagnostics
        )
    }

    private func makeMigrationAudit(
        runID: String,
        collectedAt: String,
        sourcePath: URL,
        sourceSHA256: String,
        report: XcircuiteJSONValue
    ) -> FlowRunReleaseMigrationAudit {
        let contracts = (arrayValue(value(at: ["contracts"], in: report)) ?? []).compactMap {
            item -> FlowRunReleaseMigrationAudit.ContractSummary? in
            guard let object = objectValue(item) else {
                return nil
            }
            return FlowRunReleaseMigrationAudit.ContractSummary(
                contractID: stringValue(object["id"]) ?? "",
                owner: stringValue(object["owner"]) ?? "",
                status: stringValue(object["status"]) ?? "unknown",
                expectedVersion: object["expectedVersion"],
                observedVersion: object["observedVersion"],
                requiredPathCount: intValue(object["requiredPathCount"]) ?? 0,
                failureCount: arrayValue(object["failures"])?.count ?? 0
            )
        }
        var diagnostics: [FlowDiagnostic] = []
        if stringValue(value(at: ["status"], in: report)) != "passed" {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "release-migration-audit-not-passed",
                    message: "Versioned contract fixture report status is not passed."
                )
            )
        }
        return FlowRunReleaseMigrationAudit(
            runID: runID,
            collectedAt: collectedAt,
            sourceReportPath: sourcePath.path(percentEncoded: false),
            sourceReportSHA256: sourceSHA256,
            status: stringValue(value(at: ["status"], in: report)),
            contractCount: intValue(value(at: ["contractCount"], in: report)) ?? contracts.count,
            failedContractCount: intValue(value(at: ["failedContractCount"], in: report)) ?? 0,
            contracts: contracts,
            diagnostics: diagnostics
        )
    }

    private func persistArtifacts(
        runID: String,
        projectRoot: URL,
        corpusHistory: FlowRunReleaseCorpusHistory,
        performanceEnvelope: FlowRunReleasePerformanceEnvelope,
        migrationAudit: FlowRunReleaseMigrationAudit
    ) throws -> [XcircuiteFileReference] {
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let qualificationDirectory = runDirectory.appending(path: "qualification")
        try packageStore.ensureDirectory(at: qualificationDirectory)

        let artifactSpecs: [(path: String, artifactID: String, value: any Encodable)] = [
            ("qualification/corpus-history.json", Self.corpusHistoryArtifactID, corpusHistory),
            ("qualification/performance-envelope.json", Self.performanceEnvelopeArtifactID, performanceEnvelope),
            ("qualification/migration-audit.json", Self.migrationAuditArtifactID, migrationAudit),
        ]
        var references: [XcircuiteFileReference] = []
        for spec in artifactSpecs {
            let url = runDirectory.appending(path: spec.path)
            try packageStore.writeJSON(spec.value, to: url, forProjectAt: projectRoot)
            let reference = try packageStore.fileReference(
                forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(spec.path)",
                artifactID: spec.artifactID,
                kind: .report,
                format: .json,
                inProjectAt: projectRoot,
                producedByRunID: runID
            )
            try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
            references.append(reference)
        }
        return references
    }

    private func value(
        at path: [String],
        in value: XcircuiteJSONValue?
    ) -> XcircuiteJSONValue? {
        var current = value
        for segment in path {
            guard let object = objectValue(current) else {
                return nil
            }
            current = object[segment]
        }
        return current
    }

    private func objectValue(_ value: XcircuiteJSONValue?) -> [String: XcircuiteJSONValue]? {
        guard case .object(let object) = value else {
            return nil
        }
        return object
    }

    private func arrayValue(_ value: XcircuiteJSONValue?) -> [XcircuiteJSONValue]? {
        guard case .array(let array) = value else {
            return nil
        }
        return array
    }

    private func stringValue(_ value: XcircuiteJSONValue?) -> String? {
        guard case .string(let string) = value else {
            return nil
        }
        return string
    }

    private func boolValue(_ value: XcircuiteJSONValue?) -> Bool? {
        guard case .bool(let bool) = value else {
            return nil
        }
        return bool
    }

    private func numberValue(_ value: XcircuiteJSONValue?) -> Double? {
        guard case .number(let number) = value else {
            return nil
        }
        return number
    }

    private func intValue(_ value: XcircuiteJSONValue?) -> Int? {
        guard let number = numberValue(value) else {
            return nil
        }
        return Int(number)
    }

    private func requiredObject(
        _ value: XcircuiteJSONValue?,
        source: String,
        fieldPath: String
    ) throws -> [String: XcircuiteJSONValue] {
        guard let object = objectValue(value) else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: source,
                fieldPath: fieldPath,
                expected: "object",
                actual: typeDescription(value)
            )
        }
        return object
    }

    private func requiredObject(
        at path: [String],
        in value: XcircuiteJSONValue?,
        source: String,
        prefix: String? = nil
    ) throws -> [String: XcircuiteJSONValue] {
        let fieldPath = joinedPath(path, prefix: prefix)
        return try requiredObject(
            self.value(at: path, in: value),
            source: source,
            fieldPath: fieldPath
        )
    }

    private func requiredString(
        at path: [String],
        in value: XcircuiteJSONValue?,
        source: String,
        prefix: String? = nil
    ) throws -> String {
        let fieldPath = joinedPath(path, prefix: prefix)
        guard let string = stringValue(self.value(at: path, in: value)) else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: source,
                fieldPath: fieldPath,
                expected: "string",
                actual: typeDescription(self.value(at: path, in: value))
            )
        }
        return string
    }

    private func requiredNumber(
        at path: [String],
        in value: XcircuiteJSONValue?,
        source: String,
        prefix: String? = nil
    ) throws -> Double {
        let fieldPath = joinedPath(path, prefix: prefix)
        guard let number = numberValue(self.value(at: path, in: value)) else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: source,
                fieldPath: fieldPath,
                expected: "number",
                actual: typeDescription(self.value(at: path, in: value))
            )
        }
        return number
    }

    private func requiredArray(
        at path: [String],
        in value: XcircuiteJSONValue?,
        source: String,
        prefix: String? = nil
    ) throws -> [XcircuiteJSONValue] {
        let fieldPath = joinedPath(path, prefix: prefix)
        guard let array = arrayValue(self.value(at: path, in: value)) else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: source,
                fieldPath: fieldPath,
                expected: "array",
                actual: typeDescription(self.value(at: path, in: value))
            )
        }
        return array
    }

    private func joinedPath(_ path: [String], prefix: String?) -> String {
        let suffix = path.joined(separator: ".")
        guard let prefix, !prefix.isEmpty else {
            return suffix
        }
        guard !suffix.isEmpty else {
            return prefix
        }
        return "\(prefix).\(suffix)"
    }

    private func typeDescription(_ value: XcircuiteJSONValue?) -> String {
        guard let value else {
            return "missing"
        }
        switch value {
        case .null:
            return "null"
        case .bool:
            return "bool"
        case .number:
            return "number"
        case .string:
            return "string"
        case .array:
            return "array"
        case .object:
            return "object"
        }
    }

    private func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

import CircuiteFoundation
import Foundation

public struct DefaultFlowRunReleaseEvidenceCollector: FlowRunReleaseEvidenceCollecting {
    public static let corpusHistoryArtifactID = "qualification-corpus-history"
    public static let performanceEnvelopeArtifactID = "qualification-performance-envelope"
    public static let contractAuditArtifactID = "qualification-contract-audit"

    private let storage: XcircuiteWorkspaceStore
    private let hasher: XcircuiteHasher
    private let currentDate: Date

    public init(
        storage: XcircuiteWorkspaceStore = XcircuiteWorkspaceStore(),
        hasher: XcircuiteHasher = XcircuiteHasher(),
        currentDate: Date = Date()
    ) {
        self.storage = storage
        self.hasher = hasher
        self.currentDate = currentDate
    }

    public func collectReleaseEvidence(
        runID: String,
        projectRoot: URL,
        signoffDashboardPath: URL,
        contractReportPath: URL
    ) throws -> FlowRunReleaseEvidenceCollectionResult {
        let dashboard = try loadJSONValue(from: signoffDashboardPath)
        let contractReport = try loadJSONValue(from: contractReportPath)
        try validateSignoffDashboard(dashboard)
        try validateContractReport(contractReport)
        let dashboardSHA256 = try hasher.sha256(fileAt: signoffDashboardPath)
        let contractSHA256 = try hasher.sha256(fileAt: contractReportPath)
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
        let contractAudit = try makeContractAudit(
            runID: runID,
            collectedAt: collectedAt,
            sourcePath: contractReportPath,
            sourceSHA256: contractSHA256,
            report: contractReport
        )

        let artifacts = try persistArtifacts(
            runID: runID,
            projectRoot: projectRoot,
            corpusHistory: corpusHistory,
            performanceEnvelope: performanceEnvelope,
            contractAudit: contractAudit
        )
        let diagnostics = corpusHistory.diagnostics
            + performanceEnvelope.diagnostics
            + contractAudit.diagnostics
        return FlowRunReleaseEvidenceCollectionResult(
            runID: runID,
            corpusHistory: corpusHistory,
            performanceEnvelope: performanceEnvelope,
            contractAudit: contractAudit,
            artifacts: artifacts,
            diagnostics: diagnostics
        )
    }

    private func loadJSONValue(from url: URL) throws -> XcircuiteJSONValue {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XcircuiteWorkspaceError.readFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
        do {
            return try JSONDecoder().decode(XcircuiteJSONValue.self, from: data)
        } catch {
            throw XcircuiteWorkspaceError.decodeFailed(
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

    private func validateContractReport(_ value: XcircuiteJSONValue) throws {
        let source = "contract-report"
        _ = try requiredObject(value, source: source, fieldPath: "$")
        try requireSchemaVersion(value, source: source)
        _ = try requiredString(at: ["status"], in: value, source: source)
        _ = try requiredInteger(at: ["contractCount"], in: value, source: source)
        _ = try requiredInteger(at: ["failedContractCount"], in: value, source: source)
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
            _ = try requiredValue(at: ["expectedVersion"], in: contractValue, source: source, prefix: "contracts[\(index)]")
            _ = try requiredValue(at: ["observedVersion"], in: contractValue, source: source, prefix: "contracts[\(index)]")
            _ = try requiredInteger(at: ["requiredPathCount"], in: contractValue, source: source, prefix: "contracts[\(index)]")
            _ = try requiredArray(at: ["failures"], in: contractValue, source: source, prefix: "contracts[\(index)]")
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

    private func makeContractAudit(
        runID: String,
        collectedAt: String,
        sourcePath: URL,
        sourceSHA256: String,
        report: XcircuiteJSONValue
    ) throws -> FlowRunReleaseContractAudit {
        let source = "contract-report"
        let contractValues = try requiredArray(at: ["contracts"], in: report, source: source)
        var contracts: [FlowRunReleaseContractAudit.ContractSummary] = []
        for (index, item) in contractValues.enumerated() {
            let prefix = "contracts[\(index)]"
            let object = try requiredObject(item, source: source, fieldPath: prefix)
            let contract = XcircuiteJSONValue.object(object)
            contracts.append(FlowRunReleaseContractAudit.ContractSummary(
                contractID: try requiredString(at: ["id"], in: contract, source: source, prefix: prefix),
                owner: try requiredString(at: ["owner"], in: contract, source: source, prefix: prefix),
                status: try requiredString(at: ["status"], in: contract, source: source, prefix: prefix),
                expectedVersion: try requiredValue(at: ["expectedVersion"], in: contract, source: source, prefix: prefix),
                observedVersion: try requiredValue(at: ["observedVersion"], in: contract, source: source, prefix: prefix),
                requiredPathCount: try requiredInteger(at: ["requiredPathCount"], in: contract, source: source, prefix: prefix),
                failureCount: try requiredArray(at: ["failures"], in: contract, source: source, prefix: prefix).count
            ))
        }
        var diagnostics: [FlowDiagnostic] = []
        let status = try requiredString(at: ["status"], in: report, source: source)
        if status != "passed" {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "release-contract-audit-not-passed",
                    message: "Versioned contract fixture report status is not passed."
                )
            )
        }
        return FlowRunReleaseContractAudit(
            runID: runID,
            collectedAt: collectedAt,
            sourceReportPath: sourcePath.path(percentEncoded: false),
            sourceReportSHA256: sourceSHA256,
            status: status,
            contractCount: try requiredInteger(at: ["contractCount"], in: report, source: source),
            failedContractCount: try requiredInteger(at: ["failedContractCount"], in: report, source: source),
            contracts: contracts,
            diagnostics: diagnostics
        )
    }

    private func persistArtifacts(
        runID: String,
        projectRoot: URL,
        corpusHistory: FlowRunReleaseCorpusHistory,
        performanceEnvelope: FlowRunReleasePerformanceEnvelope,
        contractAudit: FlowRunReleaseContractAudit
    ) throws -> [ArtifactReference] {
        let runDirectory = try XcircuiteWorkspace(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let qualificationDirectory = runDirectory.appending(path: "qualification")
        try storage.ensureDirectory(at: qualificationDirectory)

        let artifactSpecs: [(path: String, artifactID: String, value: any Encodable)] = [
            ("qualification/corpus-history.json", Self.corpusHistoryArtifactID, corpusHistory),
            ("qualification/performance-envelope.json", Self.performanceEnvelopeArtifactID, performanceEnvelope),
            ("qualification/contract-audit.json", Self.contractAuditArtifactID, contractAudit),
        ]
        var references: [ArtifactReference] = []
        for spec in artifactSpecs {
            let url = runDirectory.appending(path: spec.path)
            try storage.writeJSON(spec.value, to: url, forProjectAt: projectRoot)
            let reference = try storage.makeArtifactReference(
                forProjectRelativePath: "\(XcircuiteWorkspace.directoryName)/runs/\(runID)/\(spec.path)",
                artifactID: spec.artifactID,
                role: .output,
                kind: .report,
                format: .json,
                inProjectAt: projectRoot,
                producedByRunID: runID
            )
            try storage.registerArtifact(reference, runID: runID, inProjectAt: projectRoot)
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

    private func requiredValue(
        at path: [String],
        in value: XcircuiteJSONValue?,
        source: String,
        prefix: String? = nil
    ) throws -> XcircuiteJSONValue {
        let fieldPath = joinedPath(path, prefix: prefix)
        guard let result = self.value(at: path, in: value) else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: source,
                fieldPath: fieldPath,
                expected: "JSON value",
                actual: "missing"
            )
        }
        return result
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

    private func requiredInteger(
        at path: [String],
        in value: XcircuiteJSONValue?,
        source: String,
        prefix: String? = nil
    ) throws -> Int {
        let fieldPath = joinedPath(path, prefix: prefix)
        let number = try requiredNumber(
            at: path,
            in: value,
            source: source,
            prefix: prefix
        )
        guard number.rounded() == number,
              number >= Double(Int.min),
              number <= Double(Int.max) else {
            throw FlowRunReleaseEvidenceCollectionError.invalidSourceField(
                source: source,
                fieldPath: fieldPath,
                expected: "integer",
                actual: String(number)
            )
        }
        return Int(number)
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

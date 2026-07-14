import Foundation

public struct DefaultFlowRunReleaseRetentionIndexValidator: FlowRunReleaseRetentionIndexValidating {
    private let storage: any FlowExecutionStorage
    private let hasher: XcircuiteHasher

    public init(
        storage: any FlowExecutionStorage = DesignFlowStorageDefaults.makeExecutionStorage(),
        hasher: XcircuiteHasher = XcircuiteHasher()
    ) {
        self.storage = storage
        self.hasher = hasher
    }

    public func validate(
        index: FlowRunReleaseRetentionIndex,
        runID: String,
        projectRoot: URL,
        currentDate: Date,
        maximumAgeSeconds: TimeInterval?
    ) throws -> FlowRunReleaseRetentionValidationResult {
        var diagnostics: [FlowDiagnostic] = []
        func add(_ code: String, _ message: String) {
            diagnostics.append(FlowDiagnostic(severity: .error, code: code, message: message))
        }

        if index.schemaVersion != FlowRunReleaseRetentionIndex.currentSchemaVersion {
            add("retention-index-schema-unsupported", "Retention index schema version is unsupported.")
        }
        if index.runID != runID {
            add("retention-index-run-id-mismatch", "Retention index run ID does not match the requested run.")
        }
        if index.workflowRunID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("retention-index-workflow-run-id-missing", "Workflow run ID is required for CI retention evidence.")
        }
        if index.status != .passed {
            add("retention-index-status-not-passed", "Retention index status is not passed.")
        }
        if !index.appendOnly || !index.appended {
            add("retention-index-not-append-only", "Retention history is not explicitly append-only and appended.")
        }
        if index.minimumRetentionDays <= 0 || index.retentionDays < index.minimumRetentionDays {
            add("retention-index-retention-window-too-short", "Retention window is shorter than the required minimum.")
        }
        if index.previousEntryCount < 0 || index.historyEntryCount <= index.previousEntryCount {
            add("retention-index-history-not-advanced", "Retention history did not append a new entry.")
        }
        if !isSHA256(index.sourceDashboardSHA256) || !isSHA256(index.historySHA256) || !isSHA256(index.historyHeadSHA256) {
            add("retention-index-digest-invalid", "Retention index contains an invalid SHA-256 digest.")
        }
        if index.historyByteCount <= 0 || index.historyEntryCount <= 0 {
            add("retention-index-history-empty", "Retention history must contain at least one byte and one entry.")
        }

        let recordedAt = parseDate(index.recordedAt)
        if let recordedAt {
            let age = currentDate.timeIntervalSince(recordedAt)
            // ISO 8601 fractional serialization can round a Date by a few milliseconds.
            if age < -1 {
                add("retention-index-recorded-at-in-future", "Retention index recordedAt is in the future.")
            } else if let maximumAgeSeconds, age > maximumAgeSeconds {
                add("retention-index-stale", "Retention index is older than the allowed evidence age.")
            }
        } else {
            add("retention-index-recorded-at-invalid", "Retention index recordedAt is not a valid ISO 8601 timestamp.")
        }

        let dashboardURL = try resolvedProjectURL(index.sourceDashboardPath, projectRoot: projectRoot)
        let historyURL = try resolvedProjectURL(index.historyPath, projectRoot: projectRoot)
        let dashboardData = try Data(contentsOf: dashboardURL)
        let historyData = try Data(contentsOf: historyURL)
        if hasher.sha256(data: dashboardData) != index.sourceDashboardSHA256 {
            add("retention-index-dashboard-digest-mismatch", "Source dashboard digest does not match the retained index.")
        }
        if hasher.sha256(data: historyData) != index.historySHA256 {
            add("retention-index-history-digest-mismatch", "History digest does not match the retained index.")
        }
        if Int64(historyData.count) != index.historyByteCount {
            add("retention-index-history-byte-count-mismatch", "History byte count does not match the retained index.")
        }

        let entries = try decodeHistoryEntries(historyData)
        if entries.count != index.historyEntryCount {
            add("retention-index-entry-count-mismatch", "History entry count does not match the retained index.")
        }
        if entries.last?.entrySHA256 != index.historyHeadSHA256 {
            add("retention-index-head-digest-mismatch", "History head digest does not match the retained index.")
        }
        validateChain(entries, runID: runID, add: add)
        do {
            let dashboard = try JSONDecoder().decode(XcircuiteJSONValue.self, from: dashboardData)
            if let dashboardRunID = stringValue(value(at: ["runID"], in: dashboard)),
               dashboardRunID != runID {
                add("retention-index-dashboard-run-id-mismatch", "Source dashboard run ID does not match the requested run.")
            }
        } catch {
            add("retention-index-dashboard-invalid", "Source dashboard is not valid JSON: \(error.localizedDescription)")
        }

        let uniqueDiagnostics = diagnostics.reduce(into: [String: FlowDiagnostic]()) { result, diagnostic in
            result[diagnostic.code] = diagnostic
        }.values.sorted { $0.code < $1.code }
        return FlowRunReleaseRetentionValidationResult(
            status: uniqueDiagnostics.isEmpty ? .passed : .blocked,
            diagnostics: Array(uniqueDiagnostics)
        )
    }

    private func decodeHistoryEntries(_ data: Data) throws -> [FlowRunReleaseHistoryEntry] {
        guard let string = String(data: data, encoding: .utf8) else {
            throw XcircuiteWorkspaceError.decodeFailed("Retention history is not UTF-8 JSONL.")
        }
        let decoder = JSONDecoder()
        return try string.split(whereSeparator: { $0.isNewline }).map { line in
            try decoder.decode(FlowRunReleaseHistoryEntry.self, from: Data(line.utf8))
        }
    }

    private func validateChain(
        _ entries: [FlowRunReleaseHistoryEntry],
        runID: String,
        add: (String, String) -> Void
    ) {
        var entryIDs = Set<String>()
        var previousDigest: String?
        var previousDate: Date?
        for (index, entry) in entries.enumerated() {
            if !entry.isStructurallyValid {
                add("retention-index-entry-invalid", "Retention history entry (index) is structurally invalid.")
            }
            if entry.sequence != index + 1 {
                add("retention-index-sequence-gap", "Retention history sequence is not contiguous.")
            }
            if !entryIDs.insert(entry.entryID).inserted {
                add("retention-index-entry-duplicate", "Retention history contains a duplicate entry ID.")
            }
            if entry.runID != runID {
                add("retention-index-entry-run-id-mismatch", "Retention history entry run ID does not match the requested run.")
            }
            if entry.previousEntrySHA256 != previousDigest {
                add("retention-index-previous-digest-mismatch", "Retention history previous-entry digest chain is broken.")
            }
            if let date = parseDate(entry.recordedAt) {
                if let previousDate, date < previousDate {
                    add("retention-index-recorded-at-not-monotonic", "Retention history timestamps are not monotonic.")
                }
                previousDate = date
            } else {
                add("retention-index-entry-recorded-at-invalid", "Retention history entry timestamp is invalid.")
            }
            do {
                let computed = try entry.computedSHA256(using: hasher)
                if computed != entry.entrySHA256 {
                    add("retention-index-entry-digest-mismatch", "Retention history entry digest does not match its content.")
                }
            } catch {
                add("retention-index-entry-digest-uncomputable", "Retention history entry digest could not be recomputed.")
            }
            previousDigest = entry.entrySHA256
        }
    }

    private func resolvedProjectURL(_ path: String, projectRoot: URL) throws -> URL {
        try storage.url(forProjectRelativePath: path, inProjectAt: projectRoot)
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { character in
            character.isNumber || ("a"..."f").contains(character) || ("A"..."F").contains(character)
        }
    }

    private func value(at path: [String], in value: XcircuiteJSONValue) -> XcircuiteJSONValue? {
        var current: XcircuiteJSONValue? = value
        for segment in path {
            guard case .object(let object) = current else { return nil }
            current = object[segment]
        }
        return current
    }

    private func stringValue(_ value: XcircuiteJSONValue?) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }
}

import Foundation

public struct DefaultFlowRunReleaseRetentionIndexBuilder: FlowRunReleaseRetentionIndexBuilding {
    private let packageStore: any FlowExecutionStorage
    private let hasher: XcircuiteHasher
    private let validator: any FlowRunReleaseRetentionIndexValidating

    public init(
        packageStore: any FlowExecutionStorage = XcircuitePackageStore(),
        hasher: XcircuiteHasher = XcircuiteHasher(),
        validator: any FlowRunReleaseRetentionIndexValidating = DefaultFlowRunReleaseRetentionIndexValidator()
    ) {
        self.packageStore = packageStore
        self.hasher = hasher
        self.validator = validator
    }

    public func build(
        runID: String,
        workflowRunID: String,
        projectRoot: URL,
        sourceDashboardPath: String,
        historyPath: String,
        previousEntryCount: Int,
        retentionDays: Int,
        minimumRetentionDays: Int,
        recordedAt: Date
    ) throws -> FlowRunReleaseRetentionIndex {
        let dashboardURL = try packageStore.url(
            forProjectRelativePath: sourceDashboardPath,
            inProjectAt: projectRoot
        )
        let historyURL = try packageStore.url(
            forProjectRelativePath: historyPath,
            inProjectAt: projectRoot
        )
        let dashboardData = try Data(contentsOf: dashboardURL)
        let historyData = try Data(contentsOf: historyURL)
        let entries = try decodeEntries(historyData)
        let timestamp = Self.timestamp(recordedAt)
        let index = FlowRunReleaseRetentionIndex(
            runID: runID,
            workflowRunID: workflowRunID,
            recordedAt: timestamp,
            sourceDashboardPath: sourceDashboardPath,
            sourceDashboardSHA256: hasher.sha256(data: dashboardData),
            historyPath: historyPath,
            historySHA256: hasher.sha256(data: historyData),
            historyByteCount: Int64(historyData.count),
            historyEntryCount: entries.count,
            historyHeadSHA256: entries.last?.entrySHA256 ?? String(repeating: "0", count: 64),
            previousEntryCount: previousEntryCount,
            appended: entries.count > previousEntryCount,
            appendOnly: entries.count > previousEntryCount,
            retentionDays: retentionDays,
            minimumRetentionDays: minimumRetentionDays,
            status: .passed
        )
        let validation = try validator.validate(
            index: index,
            runID: runID,
            projectRoot: projectRoot,
            currentDate: recordedAt,
            maximumAgeSeconds: nil
        )
        return FlowRunReleaseRetentionIndex(
            runID: index.runID,
            workflowRunID: index.workflowRunID,
            recordedAt: index.recordedAt,
            sourceDashboardPath: index.sourceDashboardPath,
            sourceDashboardSHA256: index.sourceDashboardSHA256,
            historyPath: index.historyPath,
            historySHA256: index.historySHA256,
            historyByteCount: index.historyByteCount,
            historyEntryCount: index.historyEntryCount,
            historyHeadSHA256: index.historyHeadSHA256,
            previousEntryCount: index.previousEntryCount,
            appended: index.appended,
            appendOnly: index.appendOnly,
            retentionDays: index.retentionDays,
            minimumRetentionDays: index.minimumRetentionDays,
            status: validation.status == .passed ? .passed : .blocked,
            diagnostics: validation.diagnostics
        )
    }

    private func decodeEntries(_ data: Data) throws -> [FlowRunReleaseHistoryEntry] {
        guard let string = String(data: data, encoding: .utf8) else {
            throw XcircuitePackageError.decodeFailed("Retention history is not UTF-8 JSONL.")
        }
        let decoder = JSONDecoder()
        return try string.split(whereSeparator: { $0.isNewline }).map { line in
            try decoder.decode(FlowRunReleaseHistoryEntry.self, from: Data(line.utf8))
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

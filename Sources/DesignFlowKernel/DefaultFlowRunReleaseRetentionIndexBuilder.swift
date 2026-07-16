import CircuiteFoundation
import Foundation

public struct DefaultFlowRunReleaseRetentionIndexBuilder: FlowRunReleaseRetentionIndexBuilding {
    private let persistence: any FlowArtifactPersisting
    private let validator: any FlowRunReleaseRetentionIndexValidating

    public init(
        persistence: any FlowArtifactPersisting,
        validator: any FlowRunReleaseRetentionIndexValidating
    ) {
        self.persistence = persistence
        self.validator = validator
    }

    public func build(
        runID: String,
        workflowRunID: String,
        projectRoot: URL,
        sourceDashboard: ArtifactReference,
        history: ArtifactReference,
        previousEntryCount: Int,
        retentionDays: Int,
        minimumRetentionDays: Int,
        recordedAt: Date
    ) async throws -> FlowRunReleaseRetentionIndex {
        _ = try await persistence.loadArtifactContent(for: sourceDashboard)
        let historyData = try await persistence.loadArtifactContent(for: history)
        let entries = try decodeEntries(historyData)
        let timestamp = Self.timestamp(recordedAt)
        let index = FlowRunReleaseRetentionIndex(
            runID: runID,
            workflowRunID: workflowRunID,
            recordedAt: timestamp,
            sourceDashboardPath: sourceDashboard.locator.location.value,
            sourceDashboardSHA256: sourceDashboard.digest.hexadecimalValue,
            historyPath: history.locator.location.value,
            historySHA256: history.digest.hexadecimalValue,
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
        let validation = try await validator.validate(
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
            throw FlowRunReleaseRetentionError.invalidHistoryEncoding
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

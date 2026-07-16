import Foundation

public struct FlowRunReleaseRetentionIndex: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public enum Status: String, Sendable, Hashable, Codable {
        case passed
        case blocked
    }

    @FlowSchemaVersion1 public var schemaVersion: Int
    public var runID: String
    public var workflowRunID: String
    public var recordedAt: String
    public var sourceDashboardPath: String
    public var sourceDashboardSHA256: String
    public var historyPath: String
    public var historySHA256: String
    public var historyByteCount: Int64
    public var historyEntryCount: Int
    public var historyHeadSHA256: String
    public var previousEntryCount: Int
    public var appended: Bool
    public var appendOnly: Bool
    public var retentionDays: Int
    public var minimumRetentionDays: Int
    public var status: Status
    public var diagnostics: [FlowDiagnostic]

    public init(
        runID: String,
        workflowRunID: String,
        recordedAt: String,
        sourceDashboardPath: String,
        sourceDashboardSHA256: String,
        historyPath: String,
        historySHA256: String,
        historyByteCount: Int64,
        historyEntryCount: Int,
        historyHeadSHA256: String,
        previousEntryCount: Int,
        appended: Bool,
        appendOnly: Bool,
        retentionDays: Int,
        minimumRetentionDays: Int,
        status: Status,
        diagnostics: [FlowDiagnostic] = [],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.workflowRunID = workflowRunID
        self.recordedAt = recordedAt
        self.sourceDashboardPath = sourceDashboardPath
        self.sourceDashboardSHA256 = sourceDashboardSHA256
        self.historyPath = historyPath
        self.historySHA256 = historySHA256
        self.historyByteCount = historyByteCount
        self.historyEntryCount = historyEntryCount
        self.historyHeadSHA256 = historyHeadSHA256
        self.previousEntryCount = previousEntryCount
        self.appended = appended
        self.appendOnly = appendOnly
        self.retentionDays = retentionDays
        self.minimumRetentionDays = minimumRetentionDays
        self.status = status
        self.diagnostics = diagnostics
    }
}

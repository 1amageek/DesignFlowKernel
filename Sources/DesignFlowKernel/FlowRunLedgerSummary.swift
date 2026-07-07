import Foundation
import XcircuitePackage

public struct FlowRunLedgerSummary: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var status: FlowRunStatus
    public var runDirectoryPath: String
    public var stages: [FlowRunStageSummary]
    public var toolchain: FlowRunToolchainSummary?
    public var designDiff: FlowRunDesignDiffSummary?
    public var progressEventCount: Int
    public var latestProgressEvent: FlowRunProgressEvent?
    public var cancellationRequest: FlowRunCancellationRequest?
    public var actionCount: Int
    public var approvalCount: Int
    public var diagnostics: [FlowDiagnostic]
    public var nextActions: [FlowRunNextAction]
    public var suggestedCommandSelections: [XcircuiteSuggestedCommandSelection]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        status: FlowRunStatus,
        runDirectoryPath: String,
        stages: [FlowRunStageSummary] = [],
        toolchain: FlowRunToolchainSummary? = nil,
        designDiff: FlowRunDesignDiffSummary? = nil,
        progressEventCount: Int = 0,
        latestProgressEvent: FlowRunProgressEvent? = nil,
        cancellationRequest: FlowRunCancellationRequest? = nil,
        actionCount: Int = 0,
        approvalCount: Int = 0,
        diagnostics: [FlowDiagnostic] = [],
        nextActions: [FlowRunNextAction] = [],
        suggestedCommandSelections: [XcircuiteSuggestedCommandSelection] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.runDirectoryPath = runDirectoryPath
        self.stages = stages
        self.toolchain = toolchain
        self.designDiff = designDiff
        self.progressEventCount = progressEventCount
        self.latestProgressEvent = latestProgressEvent
        self.cancellationRequest = cancellationRequest
        self.actionCount = actionCount
        self.approvalCount = approvalCount
        self.diagnostics = diagnostics
        self.nextActions = nextActions
        self.suggestedCommandSelections = suggestedCommandSelections
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case status
        case runDirectoryPath
        case stages
        case toolchain
        case designDiff
        case progressEventCount
        case latestProgressEvent
        case cancellationRequest
        case actionCount
        case approvalCount
        case diagnostics
        case nextActions
        case suggestedCommandSelections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.runID = try container.decode(String.self, forKey: .runID)
        self.status = try container.decode(FlowRunStatus.self, forKey: .status)
        self.runDirectoryPath = try container.decode(String.self, forKey: .runDirectoryPath)
        self.stages = try container.decodeIfPresent(
            [FlowRunStageSummary].self,
            forKey: .stages
        ) ?? []
        self.toolchain = try container.decodeIfPresent(
            FlowRunToolchainSummary.self,
            forKey: .toolchain
        )
        self.designDiff = try container.decodeIfPresent(
            FlowRunDesignDiffSummary.self,
            forKey: .designDiff
        )
        self.progressEventCount = try container.decodeIfPresent(Int.self, forKey: .progressEventCount) ?? 0
        self.latestProgressEvent = try container.decodeIfPresent(
            FlowRunProgressEvent.self,
            forKey: .latestProgressEvent
        )
        self.cancellationRequest = try container.decodeIfPresent(
            FlowRunCancellationRequest.self,
            forKey: .cancellationRequest
        )
        self.actionCount = try container.decodeIfPresent(Int.self, forKey: .actionCount) ?? 0
        self.approvalCount = try container.decodeIfPresent(Int.self, forKey: .approvalCount) ?? 0
        self.diagnostics = try container.decodeIfPresent(
            [FlowDiagnostic].self,
            forKey: .diagnostics
        ) ?? []
        self.nextActions = try container.decodeIfPresent(
            [FlowRunNextAction].self,
            forKey: .nextActions
        ) ?? []
        self.suggestedCommandSelections = try container.decodeIfPresent(
            [XcircuiteSuggestedCommandSelection].self,
            forKey: .suggestedCommandSelections
        ) ?? []
    }
}

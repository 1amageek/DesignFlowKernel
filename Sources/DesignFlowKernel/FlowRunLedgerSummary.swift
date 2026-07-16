import Foundation

public struct FlowRunLedgerSummary: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public var runID: String
    public var status: FlowRunStatus
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
    public var suggestedCommandSelections: [FlowSuggestedCommandSelection]

    public init(
        runID: String,
        status: FlowRunStatus,
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
        suggestedCommandSelections: [FlowSuggestedCommandSelection] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.status = status
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
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected flow run ledger summary schema version \(Self.currentSchemaVersion)."
            )
        }
        self.runID = try container.decode(String.self, forKey: .runID)
        self.status = try container.decode(FlowRunStatus.self, forKey: .status)
        self.stages = try container.decode(
            [FlowRunStageSummary].self,
            forKey: .stages
        )
        self.toolchain = try container.decodeIfPresent(
            FlowRunToolchainSummary.self,
            forKey: .toolchain
        )
        self.designDiff = try container.decodeIfPresent(
            FlowRunDesignDiffSummary.self,
            forKey: .designDiff
        )
        self.progressEventCount = try container.decode(Int.self, forKey: .progressEventCount)
        self.latestProgressEvent = try container.decodeIfPresent(
            FlowRunProgressEvent.self,
            forKey: .latestProgressEvent
        )
        self.cancellationRequest = try container.decodeIfPresent(
            FlowRunCancellationRequest.self,
            forKey: .cancellationRequest
        )
        self.actionCount = try container.decode(Int.self, forKey: .actionCount)
        self.approvalCount = try container.decode(Int.self, forKey: .approvalCount)
        self.diagnostics = try container.decode(
            [FlowDiagnostic].self,
            forKey: .diagnostics
        )
        self.nextActions = try container.decode(
            [FlowRunNextAction].self,
            forKey: .nextActions
        )
        self.suggestedCommandSelections = try container.decode(
            [FlowSuggestedCommandSelection].self,
            forKey: .suggestedCommandSelections
        )
    }
}

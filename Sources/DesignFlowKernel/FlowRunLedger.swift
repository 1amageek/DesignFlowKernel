import Foundation

public struct FlowRunLedger: Sendable, Hashable, Codable {
    public var runID: String
    public var runDirectory: URL
    public var runManifest: XcircuiteRunManifest
    public var plan: FlowRunPlan?
    public var stages: [FlowStageResult]
    public var toolchain: FlowToolchainManifest?
    public var designDiff: XcircuiteDesignDiff?
    public var progressEvents: [FlowRunProgressEvent]
    public var cancellationRequest: FlowRunCancellationRequest?
    public var actions: [XcircuiteRunActionRecord]
    public var suggestedCommandSelections: [XcircuiteSuggestedCommandSelection]
    public var approvals: [XcircuiteApprovalRecord]

    public init(
        runID: String,
        runDirectory: URL,
        runManifest: XcircuiteRunManifest,
        plan: FlowRunPlan? = nil,
        stages: [FlowStageResult],
        toolchain: FlowToolchainManifest? = nil,
        designDiff: XcircuiteDesignDiff? = nil,
        progressEvents: [FlowRunProgressEvent] = [],
        cancellationRequest: FlowRunCancellationRequest? = nil,
        actions: [XcircuiteRunActionRecord] = [],
        suggestedCommandSelections: [XcircuiteSuggestedCommandSelection] = [],
        approvals: [XcircuiteApprovalRecord] = []
    ) {
        self.runID = runID
        self.runDirectory = runDirectory
        self.runManifest = runManifest
        self.plan = plan
        self.stages = stages
        self.toolchain = toolchain
        self.designDiff = designDiff
        self.progressEvents = progressEvents
        self.cancellationRequest = cancellationRequest
        self.actions = actions
        self.suggestedCommandSelections = suggestedCommandSelections
        self.approvals = approvals
    }

    public var runResult: FlowRunResult {
        FlowRunResult(
            runID: runID,
            status: flowStatus(runManifest.status),
            runDirectory: runDirectory,
            stages: stages
        )
    }

    private func flowStatus(_ status: XcircuiteRunStatus) -> FlowRunStatus {
        switch status {
        case .created:
            .created
        case .running:
            .running
        case .succeeded:
            .succeeded
        case .failed:
            .failed
        case .cancelled:
            .cancelled
        case .blocked:
            .blocked
        case .partial:
            .partial
        }
    }
}

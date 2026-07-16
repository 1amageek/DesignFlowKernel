import Foundation

public struct FlowLoopIterationSummary: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case running
        case succeeded
        case failed
        case cancelled
        case blocked
        case partial
        case unknown
    }

    public struct EvaluationDelta: Sendable, Hashable, Codable {
        public var acceptedCount: Int
        public var rejectedCount: Int
        public var needsHumanReviewCount: Int
        public var blockedCount: Int
        public var inconclusiveCount: Int
        public var failedDiagnosticCount: Int
        public var changedMetricIDs: [String]

        public init(
            acceptedCount: Int = 0,
            rejectedCount: Int = 0,
            needsHumanReviewCount: Int = 0,
            blockedCount: Int = 0,
            inconclusiveCount: Int = 0,
            failedDiagnosticCount: Int = 0,
            changedMetricIDs: [String] = []
        ) {
            self.acceptedCount = acceptedCount
            self.rejectedCount = rejectedCount
            self.needsHumanReviewCount = needsHumanReviewCount
            self.blockedCount = blockedCount
            self.inconclusiveCount = inconclusiveCount
            self.failedDiagnosticCount = failedDiagnosticCount
            self.changedMetricIDs = changedMetricIDs
        }
    }

    public struct RiskSignal: Sendable, Hashable, Codable {
        public var signalID: String
        public var detectorID: String
        public var severity: FlowRunGuardSeverity
        public var reason: String
        public var actionIDs: [String]
        public var artifactIDs: [String]
        public var diagnosticCode: String?

        public init(
            signalID: String,
            detectorID: String,
            severity: FlowRunGuardSeverity,
            reason: String,
            actionIDs: [String] = [],
            artifactIDs: [String] = [],
            diagnosticCode: String? = nil
        ) {
            self.signalID = signalID
            self.detectorID = detectorID
            self.severity = severity
            self.reason = reason
            self.actionIDs = actionIDs
            self.artifactIDs = artifactIDs
            self.diagnosticCode = diagnosticCode
        }
    }

    public var schemaVersion: Int
    public var iterationID: String
    public var runID: String
    public var ordinal: Int
    public var status: Status
    public var actionIDs: [String]
    public var actionKinds: [String]
    public var startedAt: Date?
    public var completedAt: Date?
    public var inputArtifactIDs: [String]
    public var outputArtifactIDs: [String]
    public var designDiffID: String?
    public var evaluationDelta: EvaluationDelta
    public var riskSignals: [RiskSignal]

    public init(
        schemaVersion: Int = 1,
        iterationID: String,
        runID: String,
        ordinal: Int,
        status: Status,
        actionIDs: [String] = [],
        actionKinds: [String] = [],
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        inputArtifactIDs: [String] = [],
        outputArtifactIDs: [String] = [],
        designDiffID: String? = nil,
        evaluationDelta: EvaluationDelta = EvaluationDelta(),
        riskSignals: [RiskSignal] = []
    ) {
        self.schemaVersion = schemaVersion
        self.iterationID = iterationID
        self.runID = runID
        self.ordinal = ordinal
        self.status = status
        self.actionIDs = actionIDs
        self.actionKinds = actionKinds
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.inputArtifactIDs = inputArtifactIDs
        self.outputArtifactIDs = outputArtifactIDs
        self.designDiffID = designDiffID
        self.evaluationDelta = evaluationDelta
        self.riskSignals = riskSignals
    }
}

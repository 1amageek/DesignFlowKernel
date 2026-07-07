import Foundation

public enum FlowRunReviewItemKind: String, Sendable, Hashable, Codable {
    case designDiff
    case approvalGate
    case toolTrust
    case stageFailure
    case stageBlocker
    case diagnosticReview
    case artifactIntegrity
    case artifactCoverage
    case planningCorrectness
    case retainedHistory
    case cancellation
    case archiveOrContinue
}

public enum FlowRunReviewItemStatus: String, Sendable, Hashable, Codable {
    case needsReview
    case readyToResume
    case needsRepair
    case informational
    case closed
}

public struct FlowRunReviewItem: Sendable, Hashable, Codable {
    public var itemID: String
    public var kind: FlowRunReviewItemKind
    public var status: FlowRunReviewItemStatus
    public var stageID: String?
    public var severity: FlowDiagnosticSeverity
    public var title: String
    public var reason: String
    public var diagnosticCodes: [String]
    public var artifactPaths: [String]
    public var nextActionID: String?

    public init(
        itemID: String,
        kind: FlowRunReviewItemKind,
        status: FlowRunReviewItemStatus,
        stageID: String? = nil,
        severity: FlowDiagnosticSeverity,
        title: String,
        reason: String,
        diagnosticCodes: [String] = [],
        artifactPaths: [String] = [],
        nextActionID: String? = nil
    ) {
        self.itemID = itemID
        self.kind = kind
        self.status = status
        self.stageID = stageID
        self.severity = severity
        self.title = title
        self.reason = reason
        self.diagnosticCodes = diagnosticCodes
        self.artifactPaths = artifactPaths
        self.nextActionID = nextActionID
    }
}

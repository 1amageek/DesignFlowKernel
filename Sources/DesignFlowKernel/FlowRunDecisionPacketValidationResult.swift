import Foundation

public struct FlowRunDecisionPacketValidationResult: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case passed
        case needsReview
        case blocked
    }

    public var schemaVersion: Int
    public var runID: String
    public var packetPath: String
    public var validationArtifactPath: String?
    public var status: Status
    public var packetReadiness: FlowRunDecisionPacket.Readiness?
    public var packetArtifactIntegrity: XcircuiteFileReferenceIntegrity?
    public var requiredArtifactCount: Int
    public var satisfiedRequiredArtifactCount: Int
    public var missingRequiredArtifactCount: Int
    public var invalidRequiredArtifactCount: Int
    public var unresolvedReviewItemCount: Int
    public var completionIssueCount: Int
    public var replayCommandCount: Int
    public var diagnostics: [FlowDiagnostic]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        packetPath: String,
        validationArtifactPath: String? = nil,
        status: Status,
        packetReadiness: FlowRunDecisionPacket.Readiness? = nil,
        packetArtifactIntegrity: XcircuiteFileReferenceIntegrity? = nil,
        requiredArtifactCount: Int = 0,
        satisfiedRequiredArtifactCount: Int = 0,
        missingRequiredArtifactCount: Int = 0,
        invalidRequiredArtifactCount: Int = 0,
        unresolvedReviewItemCount: Int = 0,
        completionIssueCount: Int = 0,
        replayCommandCount: Int = 0,
        diagnostics: [FlowDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.packetPath = packetPath
        self.validationArtifactPath = validationArtifactPath
        self.status = status
        self.packetReadiness = packetReadiness
        self.packetArtifactIntegrity = packetArtifactIntegrity
        self.requiredArtifactCount = requiredArtifactCount
        self.satisfiedRequiredArtifactCount = satisfiedRequiredArtifactCount
        self.missingRequiredArtifactCount = missingRequiredArtifactCount
        self.invalidRequiredArtifactCount = invalidRequiredArtifactCount
        self.unresolvedReviewItemCount = unresolvedReviewItemCount
        self.completionIssueCount = completionIssueCount
        self.replayCommandCount = replayCommandCount
        self.diagnostics = diagnostics
    }
}

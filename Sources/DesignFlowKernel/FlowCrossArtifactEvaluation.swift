import Foundation

public struct FlowCrossArtifactEvaluation: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var evaluationID: String
    public var runID: String
    public var profileID: String?
    public var status: FlowEvaluationStatus
    public var generatedAt: Date
    public var artifactIDs: [String]
    public var channelResults: [FlowEvaluationChannelResult]
    public var diagnostics: [FlowRunDiagnostic]
    public var summary: String

    public init(
        schemaVersion: Int = 1,
        evaluationID: String,
        runID: String,
        profileID: String? = nil,
        status: FlowEvaluationStatus,
        generatedAt: Date = Date(),
        artifactIDs: [String] = [],
        channelResults: [FlowEvaluationChannelResult] = [],
        diagnostics: [FlowRunDiagnostic] = [],
        summary: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.evaluationID = evaluationID
        self.runID = runID
        self.profileID = profileID
        self.status = status
        self.generatedAt = generatedAt
        self.artifactIDs = artifactIDs
        self.channelResults = channelResults
        self.diagnostics = diagnostics
        self.summary = summary
    }
}

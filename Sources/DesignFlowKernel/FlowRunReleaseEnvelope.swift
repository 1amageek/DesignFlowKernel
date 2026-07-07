import Foundation
import XcircuitePackage

public struct FlowRunReleaseEnvelope: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case passed
        case needsReview
        case blocked
    }

    public struct Requirement: Sendable, Hashable, Codable {
        public var requirementID: String
        public var title: String
        public var required: Bool
        public var status: Status
        public var purpose: String
        public var artifactIDs: [String]
        public var artifactPaths: [String]
        public var artifactIntegrity: [XcircuiteFileReferenceIntegrity]
        public var diagnosticCodes: [String]

        public init(
            requirementID: String,
            title: String,
            required: Bool,
            status: Status,
            purpose: String,
            artifactIDs: [String] = [],
            artifactPaths: [String] = [],
            artifactIntegrity: [XcircuiteFileReferenceIntegrity] = [],
            diagnosticCodes: [String] = []
        ) {
            self.requirementID = requirementID
            self.title = title
            self.required = required
            self.status = status
            self.purpose = purpose
            self.artifactIDs = artifactIDs
            self.artifactPaths = artifactPaths
            self.artifactIntegrity = artifactIntegrity
            self.diagnosticCodes = diagnosticCodes
        }
    }

    public var schemaVersion: Int
    public var envelopeID: String
    public var runID: String
    public var status: Status
    public var decisionPacketValidation: FlowRunDecisionPacketValidationResult
    public var requirements: [Requirement]
    public var diagnostics: [FlowDiagnostic]
    public var replayCommands: [FlowRunSuggestedCommand]

    public init(
        schemaVersion: Int = 1,
        envelopeID: String,
        runID: String,
        status: Status,
        decisionPacketValidation: FlowRunDecisionPacketValidationResult,
        requirements: [Requirement],
        diagnostics: [FlowDiagnostic] = [],
        replayCommands: [FlowRunSuggestedCommand] = []
    ) {
        self.schemaVersion = schemaVersion
        self.envelopeID = envelopeID
        self.runID = runID
        self.status = status
        self.decisionPacketValidation = decisionPacketValidation
        self.requirements = requirements
        self.diagnostics = diagnostics
        self.replayCommands = replayCommands
    }
}

import CircuiteFoundation
import Foundation

public struct FlowRunGuardVerdict: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case `continue`
        case needsHumanReview
        case blocked
        case cancelled
    }

    public struct DetectorResult: Sendable, Hashable, Codable {
        public var detectorID: String
        public var severity: FlowRunGuardSeverity
        public var reason: String
        public var actionIDs: [String]
        public var artifactIDs: [String]
        public var diagnosticCodes: [String]

        public init(
            detectorID: String,
            severity: FlowRunGuardSeverity,
            reason: String,
            actionIDs: [String] = [],
            artifactIDs: [String] = [],
            diagnosticCodes: [String] = []
        ) {
            self.detectorID = detectorID
            self.severity = severity
            self.reason = reason
            self.actionIDs = actionIDs
            self.artifactIDs = artifactIDs
            self.diagnosticCodes = diagnosticCodes
        }
    }

    public struct RequiredAction: Sendable, Hashable, Codable {
        public var actionID: String
        public var kind: String
        public var severity: FlowRunGuardSeverity
        public var reason: String
        public var artifactIDs: [String]
        public var stageIDs: [String]

        public init(
            actionID: String,
            kind: String,
            severity: FlowRunGuardSeverity,
            reason: String,
            artifactIDs: [String] = [],
            stageIDs: [String] = []
        ) {
            self.actionID = actionID
            self.kind = kind
            self.severity = severity
            self.reason = reason
            self.artifactIDs = artifactIDs
            self.stageIDs = stageIDs
        }
    }

    public struct SuggestedCommand: Sendable, Hashable, Codable {
        public var commandID: String
        public var executable: String
        public var arguments: [String]
        public var reason: String
        public var readiness: String

        public init(
            commandID: String,
            executable: String,
            arguments: [String],
            reason: String,
            readiness: String = "ready"
        ) {
            self.commandID = commandID
            self.executable = executable
            self.arguments = arguments
            self.reason = reason
            self.readiness = readiness
        }
    }

    @FlowSchemaVersion1 public var schemaVersion: Int
    public var verdictID: String
    public var runID: String
    public var profileID: String
    public var snapshotID: String
    public var status: Status
    public var generatedAt: Date
    public var triggeredDetectors: [DetectorResult]
    public var requiredActions: [RequiredAction]
    public var suggestedCommands: [SuggestedCommand]
    /// Canonical artifacts used as evidence for this verdict.
    public var artifactReferences: [ArtifactReference]

    public init(
        schemaVersion: Int = 1,
        verdictID: String,
        runID: String,
        profileID: String,
        snapshotID: String,
        status: Status,
        generatedAt: Date = Date(),
        triggeredDetectors: [DetectorResult] = [],
        requiredActions: [RequiredAction] = [],
        suggestedCommands: [SuggestedCommand] = [],
        artifactReferences: [ArtifactReference] = []
    ) {
        self.schemaVersion = schemaVersion
        self.verdictID = verdictID
        self.runID = runID
        self.profileID = profileID
        self.snapshotID = snapshotID
        self.status = status
        self.generatedAt = generatedAt
        self.triggeredDetectors = triggeredDetectors
        self.requiredActions = requiredActions
        self.suggestedCommands = suggestedCommands
        self.artifactReferences = artifactReferences
    }
}

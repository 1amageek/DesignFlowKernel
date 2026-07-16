import Foundation

public struct FlowAgentLoopProfile: Sendable, Hashable, Codable {
    public struct Scope: Sendable, Hashable, Codable {
        public enum Kind: String, Sendable, Hashable, Codable {
            case project
            case cell
            case run
            case stage
        }

        public var kind: Kind
        public var identifier: String?

        public init(kind: Kind = .run, identifier: String? = nil) {
            self.kind = kind
            self.identifier = identifier
        }
    }

    public struct Budgets: Sendable, Hashable, Codable {
        public var maxActions: Int?
        public var maxElapsedSeconds: Int?
        public var maxToolInvocations: Int?
        public var maxChangedFiles: Int?
        public var maxDesignChanges: Int?

        public init(
            maxActions: Int? = nil,
            maxElapsedSeconds: Int? = nil,
            maxToolInvocations: Int? = nil,
            maxChangedFiles: Int? = nil,
            maxDesignChanges: Int? = nil
        ) {
            self.maxActions = maxActions
            self.maxElapsedSeconds = maxElapsedSeconds
            self.maxToolInvocations = maxToolInvocations
            self.maxChangedFiles = maxChangedFiles
            self.maxDesignChanges = maxDesignChanges
        }
    }

    public struct RequiredEvidence: Sendable, Hashable, Codable {
        public var evidenceID: String
        public var artifactRole: String
        public var artifactID: String?
        public var stageID: String?
        public var maximumAgeSeconds: Int?
        public var required: Bool

        public init(
            evidenceID: String,
            artifactRole: String,
            artifactID: String? = nil,
            stageID: String? = nil,
            maximumAgeSeconds: Int? = nil,
            required: Bool = true
        ) {
            self.evidenceID = evidenceID
            self.artifactRole = artifactRole
            self.artifactID = artifactID
            self.stageID = stageID
            self.maximumAgeSeconds = maximumAgeSeconds
            self.required = required
        }
    }

    public struct DetectorPolicy: Sendable, Hashable, Codable {
        public var detectorID: String
        public var enabled: Bool
        public var threshold: Double?
        public var windowSize: Int?

        public init(
            detectorID: String,
            enabled: Bool = true,
            threshold: Double? = nil,
            windowSize: Int? = nil
        ) {
            self.detectorID = detectorID
            self.enabled = enabled
            self.threshold = threshold
            self.windowSize = windowSize
        }
    }

    public struct ApprovalThreshold: Sendable, Hashable, Codable {
        public var operationKind: String
        public var minimumSeverity: FlowRunGuardSeverity

        public init(
            operationKind: String,
            minimumSeverity: FlowRunGuardSeverity = .warning
        ) {
            self.operationKind = operationKind
            self.minimumSeverity = minimumSeverity
        }
    }

    public struct ResumePolicy: Sendable, Hashable, Codable {
        public var allowedStatuses: [FlowRunStatus]
        public var requireFreshSnapshot: Bool
        public var requireGuardVerdict: Bool

        public init(
            allowedStatuses: [FlowRunStatus] = [.created, .partial, .blocked, .failed],
            requireFreshSnapshot: Bool = true,
            requireGuardVerdict: Bool = true
        ) {
            self.allowedStatuses = allowedStatuses
            self.requireFreshSnapshot = requireFreshSnapshot
            self.requireGuardVerdict = requireGuardVerdict
        }
    }

    public var schemaVersion: Int
    public var profileID: String
    public var scope: Scope
    public var budgets: Budgets
    public var requiredEvidence: [RequiredEvidence]
    public var detectors: [DetectorPolicy]
    public var approvalThresholds: [ApprovalThreshold]
    public var resumePolicy: ResumePolicy

    public init(
        schemaVersion: Int = 1,
        profileID: String,
        scope: Scope = Scope(),
        budgets: Budgets = Budgets(),
        requiredEvidence: [RequiredEvidence] = [],
        detectors: [DetectorPolicy] = Self.defaultDetectors,
        approvalThresholds: [ApprovalThreshold] = [],
        resumePolicy: ResumePolicy = ResumePolicy()
    ) {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.scope = scope
        self.budgets = budgets
        self.requiredEvidence = requiredEvidence
        self.detectors = detectors
        self.approvalThresholds = approvalThresholds
        self.resumePolicy = resumePolicy
    }

    public static var defaultDetectors: [DetectorPolicy] {
        [
            DetectorPolicy(detectorID: "budgetExceeded"),
            DetectorPolicy(detectorID: "missingRequiredEvidence"),
            DetectorPolicy(detectorID: "staleEvidence"),
            DetectorPolicy(detectorID: "verificationBypass"),
            DetectorPolicy(detectorID: "noProgress", threshold: 5),
            DetectorPolicy(detectorID: "repeatedAction", threshold: 3),
            DetectorPolicy(detectorID: "oscillation", enabled: false, threshold: 3),
            DetectorPolicy(detectorID: "worseningTrend"),
            DetectorPolicy(detectorID: "toolFailureBurst", threshold: 3),
            DetectorPolicy(detectorID: "changeMagnitudeExceeded"),
            DetectorPolicy(detectorID: "approvalRequired"),
        ]
    }

    public static func makeDefault(profileID: String = "default-agent-loop-profile") -> Self {
        Self(
            profileID: profileID,
            budgets: Budgets(maxActions: 50, maxElapsedSeconds: 3_600, maxToolInvocations: 50),
            requiredEvidence: [],
            detectors: defaultDetectors,
            approvalThresholds: [
                ApprovalThreshold(operationKind: "layout"),
                ApprovalThreshold(operationKind: "signoff"),
                ApprovalThreshold(operationKind: "verification"),
            ]
        )
    }
}

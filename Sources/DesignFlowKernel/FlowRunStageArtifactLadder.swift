import Foundation
import XcircuitePackage

public struct FlowRunStageArtifactLadder: Sendable, Hashable, Codable {
    public enum Readiness: String, Sendable, Hashable, Codable {
        case ready
        case needsReview
        case blocked
    }

    public struct Summary: Sendable, Hashable, Codable {
        public var stageCount: Int
        public var runArtifactCount: Int
        public var stageArtifactCount: Int
        public var retryArtifactCount: Int
        public var reviewItemCount: Int
        public var unresolvedReviewItemCount: Int
        public var invalidArtifactCount: Int
        public var artifactCoverageIssueCount: Int
        public var domainCounts: [String: Int]
        public var stageCategoryCounts: [String: Int]?
        public var handoffRefCount: Int?
        public var statusRefCount: Int?

        public init(
            stageCount: Int,
            runArtifactCount: Int,
            stageArtifactCount: Int,
            retryArtifactCount: Int,
            reviewItemCount: Int,
            unresolvedReviewItemCount: Int,
            invalidArtifactCount: Int,
            artifactCoverageIssueCount: Int,
            domainCounts: [String: Int] = [:],
            stageCategoryCounts: [String: Int]? = nil,
            handoffRefCount: Int? = nil,
            statusRefCount: Int? = nil
        ) {
            self.stageCount = stageCount
            self.runArtifactCount = runArtifactCount
            self.stageArtifactCount = stageArtifactCount
            self.retryArtifactCount = retryArtifactCount
            self.reviewItemCount = reviewItemCount
            self.unresolvedReviewItemCount = unresolvedReviewItemCount
            self.invalidArtifactCount = invalidArtifactCount
            self.artifactCoverageIssueCount = artifactCoverageIssueCount
            self.domainCounts = domainCounts
            self.stageCategoryCounts = stageCategoryCounts
            self.handoffRefCount = handoffRefCount
            self.statusRefCount = statusRefCount
        }

        private enum CodingKeys: String, CodingKey {
            case stageCount
            case runArtifactCount
            case stageArtifactCount
            case retryArtifactCount
            case reviewItemCount
            case unresolvedReviewItemCount
            case invalidArtifactCount
            case artifactCoverageIssueCount
            case domainCounts
            case stageCategoryCounts
            case handoffRefCount
            case statusRefCount
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stageCount = try container.decodeIfPresent(Int.self, forKey: .stageCount) ?? 0
            runArtifactCount = try container.decodeIfPresent(Int.self, forKey: .runArtifactCount) ?? 0
            stageArtifactCount = try container.decodeIfPresent(Int.self, forKey: .stageArtifactCount) ?? 0
            retryArtifactCount = try container.decodeIfPresent(Int.self, forKey: .retryArtifactCount) ?? 0
            reviewItemCount = try container.decodeIfPresent(Int.self, forKey: .reviewItemCount) ?? 0
            unresolvedReviewItemCount = try container.decodeIfPresent(
                Int.self,
                forKey: .unresolvedReviewItemCount
            ) ?? 0
            invalidArtifactCount = try container.decodeIfPresent(Int.self, forKey: .invalidArtifactCount) ?? 0
            artifactCoverageIssueCount = try container.decodeIfPresent(
                Int.self,
                forKey: .artifactCoverageIssueCount
            ) ?? 0
            domainCounts = try container.decodeIfPresent([String: Int].self, forKey: .domainCounts) ?? [:]
            stageCategoryCounts = try container.decodeIfPresent(
                [String: Int].self,
                forKey: .stageCategoryCounts
            )
            handoffRefCount = try container.decodeIfPresent(Int.self, forKey: .handoffRefCount)
            statusRefCount = try container.decodeIfPresent(Int.self, forKey: .statusRefCount)
        }
    }

    public struct Artifact: Sendable, Hashable, Codable {
        public var role: String
        public var domain: String
        public var artifactID: String?
        public var stageID: String?
        public var path: String
        public var kind: XcircuiteFileKind
        public var format: XcircuiteFileFormat
        public var sha256: String?
        public var byteCount: Int64?
        public var integrity: FlowRunReviewArtifactIntegrity?
        public var statusRef: String?
        public var handoffRole: String?

        public init(
            role: String,
            domain: String,
            artifactID: String? = nil,
            stageID: String? = nil,
            path: String,
            kind: XcircuiteFileKind,
            format: XcircuiteFileFormat,
            sha256: String? = nil,
            byteCount: Int64? = nil,
            integrity: FlowRunReviewArtifactIntegrity? = nil,
            statusRef: String? = nil,
            handoffRole: String? = nil
        ) {
            self.role = role
            self.domain = domain
            self.artifactID = artifactID
            self.stageID = stageID
            self.path = path
            self.kind = kind
            self.format = format
            self.sha256 = sha256
            self.byteCount = byteCount
            self.integrity = integrity
            self.statusRef = statusRef
            self.handoffRole = handoffRole
        }
    }

    public struct HandoffRef: Sendable, Hashable, Codable {
        public var role: String
        public var fromStageID: String?
        public var toStageID: String?
        public var artifactID: String?
        public var artifactPath: String
        public var domain: String
        public var statusRef: String?
        public var sha256: String?
        public var byteCount: Int64?

        public init(
            role: String,
            fromStageID: String? = nil,
            toStageID: String? = nil,
            artifactID: String? = nil,
            artifactPath: String,
            domain: String,
            statusRef: String? = nil,
            sha256: String? = nil,
            byteCount: Int64? = nil
        ) {
            self.role = role
            self.fromStageID = fromStageID
            self.toStageID = toStageID
            self.artifactID = artifactID
            self.artifactPath = artifactPath
            self.domain = domain
            self.statusRef = statusRef
            self.sha256 = sha256
            self.byteCount = byteCount
        }
    }

    public struct RetryRef: Sendable, Hashable, Codable {
        public var stageID: String
        public var attemptIndex: Int
        public var status: FlowStageStatus
        public var shouldRetry: Bool
        public var reason: FlowStageRetryDecisionReason
        public var diagnosticCodes: [String]

        public init(
            stageID: String,
            attemptIndex: Int,
            status: FlowStageStatus,
            shouldRetry: Bool,
            reason: FlowStageRetryDecisionReason,
            diagnosticCodes: [String] = []
        ) {
            self.stageID = stageID
            self.attemptIndex = attemptIndex
            self.status = status
            self.shouldRetry = shouldRetry
            self.reason = reason
            self.diagnosticCodes = diagnosticCodes
        }

        private enum CodingKeys: String, CodingKey {
            case stageID
            case attemptIndex
            case status
            case shouldRetry
            case reason
            case diagnosticCodes
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stageID = try container.decode(String.self, forKey: .stageID)
            attemptIndex = try container.decode(Int.self, forKey: .attemptIndex)
            status = try container.decode(FlowStageStatus.self, forKey: .status)
            shouldRetry = try container.decode(Bool.self, forKey: .shouldRetry)
            reason = try container.decode(FlowStageRetryDecisionReason.self, forKey: .reason)
            diagnosticCodes = try container.decodeIfPresent([String].self, forKey: .diagnosticCodes) ?? []
        }
    }

    public struct RoleCoverage: Sendable, Hashable, Codable {
        public var role: String
        public var artifactCount: Int
        public var verifiedCount: Int
        public var issueCount: Int
        public var artifactPaths: [String]

        public init(
            role: String,
            artifactCount: Int,
            verifiedCount: Int,
            issueCount: Int,
            artifactPaths: [String] = []
        ) {
            self.role = role
            self.artifactCount = artifactCount
            self.verifiedCount = verifiedCount
            self.issueCount = issueCount
            self.artifactPaths = artifactPaths
        }

        private enum CodingKeys: String, CodingKey {
            case role
            case artifactCount
            case verifiedCount
            case issueCount
            case artifactPaths
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decode(String.self, forKey: .role)
            artifactCount = try container.decodeIfPresent(Int.self, forKey: .artifactCount) ?? 0
            verifiedCount = try container.decodeIfPresent(Int.self, forKey: .verifiedCount) ?? 0
            issueCount = try container.decodeIfPresent(Int.self, forKey: .issueCount) ?? 0
            artifactPaths = try container.decodeIfPresent([String].self, forKey: .artifactPaths) ?? []
        }
    }

    public struct SignoffManifestCoverage: Sendable, Hashable, Codable {
        public var requiredRoles: [String]
        public var satisfiedRoles: [String]
        public var missingRoles: [String]
        public var artifactPathsByRole: [String: [String]]
        public var unsignedArtifactPaths: [String]
        public var allRequiredArtifactsHaveHashesAndByteCounts: Bool

        public init(
            requiredRoles: [String],
            satisfiedRoles: [String],
            missingRoles: [String],
            artifactPathsByRole: [String: [String]] = [:],
            unsignedArtifactPaths: [String] = [],
            allRequiredArtifactsHaveHashesAndByteCounts: Bool
        ) {
            self.requiredRoles = requiredRoles
            self.satisfiedRoles = satisfiedRoles
            self.missingRoles = missingRoles
            self.artifactPathsByRole = artifactPathsByRole
            self.unsignedArtifactPaths = unsignedArtifactPaths
            self.allRequiredArtifactsHaveHashesAndByteCounts = allRequiredArtifactsHaveHashesAndByteCounts
        }

        private enum CodingKeys: String, CodingKey {
            case requiredRoles
            case satisfiedRoles
            case missingRoles
            case artifactPathsByRole
            case unsignedArtifactPaths
            case allRequiredArtifactsHaveHashesAndByteCounts
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            requiredRoles = try container.decodeIfPresent([String].self, forKey: .requiredRoles) ?? []
            satisfiedRoles = try container.decodeIfPresent([String].self, forKey: .satisfiedRoles) ?? []
            missingRoles = try container.decodeIfPresent([String].self, forKey: .missingRoles) ?? []
            artifactPathsByRole = try container.decodeIfPresent(
                [String: [String]].self,
                forKey: .artifactPathsByRole
            ) ?? [:]
            unsignedArtifactPaths = try container.decodeIfPresent([String].self, forKey: .unsignedArtifactPaths) ?? []
            allRequiredArtifactsHaveHashesAndByteCounts = try container.decodeIfPresent(
                Bool.self,
                forKey: .allRequiredArtifactsHaveHashesAndByteCounts
            ) ?? false
        }
    }

    public struct Stage: Sendable, Hashable, Codable {
        public var index: Int
        public var stageID: String
        public var status: FlowStageStatus
        public var gates: [FlowRunGateSummary]
        public var diagnosticCodes: [String]
        public var artifactCount: Int
        public var attemptCount: Int
        public var retryCount: Int
        public var category: String?
        public var statusRef: String?
        public var domains: [String]
        public var roleCoverage: [RoleCoverage]
        public var artifacts: [Artifact]
        public var handoffRefs: [HandoffRef]?
        public var retryRefs: [RetryRef]?
        public var attempts: [FlowStageAttemptRecord]
        public var reviewItems: [FlowRunReviewItem]
        public var nextActions: [FlowRunNextAction]

        public init(
            index: Int,
            stageID: String,
            status: FlowStageStatus,
            gates: [FlowRunGateSummary] = [],
            diagnosticCodes: [String] = [],
            artifactCount: Int = 0,
            attemptCount: Int = 0,
            retryCount: Int = 0,
            category: String? = nil,
            statusRef: String? = nil,
            domains: [String] = [],
            roleCoverage: [RoleCoverage] = [],
            artifacts: [Artifact] = [],
            handoffRefs: [HandoffRef]? = nil,
            retryRefs: [RetryRef]? = nil,
            attempts: [FlowStageAttemptRecord] = [],
            reviewItems: [FlowRunReviewItem] = [],
            nextActions: [FlowRunNextAction] = []
        ) {
            self.index = index
            self.stageID = stageID
            self.status = status
            self.gates = gates
            self.diagnosticCodes = diagnosticCodes
            self.artifactCount = artifactCount
            self.attemptCount = attemptCount
            self.retryCount = retryCount
            self.category = category
            self.statusRef = statusRef
            self.domains = domains
            self.roleCoverage = roleCoverage
            self.artifacts = artifacts
            self.handoffRefs = handoffRefs
            self.retryRefs = retryRefs
            self.attempts = attempts
            self.reviewItems = reviewItems
            self.nextActions = nextActions
        }

        private enum CodingKeys: String, CodingKey {
            case index
            case stageID
            case status
            case gates
            case diagnosticCodes
            case artifactCount
            case attemptCount
            case retryCount
            case category
            case statusRef
            case domains
            case roleCoverage
            case artifacts
            case handoffRefs
            case retryRefs
            case attempts
            case reviewItems
            case nextActions
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
            stageID = try container.decode(String.self, forKey: .stageID)
            status = try container.decode(FlowStageStatus.self, forKey: .status)
            gates = try container.decodeIfPresent([FlowRunGateSummary].self, forKey: .gates) ?? []
            diagnosticCodes = try container.decodeIfPresent([String].self, forKey: .diagnosticCodes) ?? []
            artifacts = try container.decodeIfPresent([Artifact].self, forKey: .artifacts) ?? []
            attempts = try container.decodeIfPresent([FlowStageAttemptRecord].self, forKey: .attempts) ?? []
            roleCoverage = try container.decodeIfPresent([RoleCoverage].self, forKey: .roleCoverage) ?? []
            artifactCount = try container.decodeIfPresent(Int.self, forKey: .artifactCount) ?? artifacts.count
            attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? attempts.count
            retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
            category = try container.decodeIfPresent(String.self, forKey: .category)
            statusRef = try container.decodeIfPresent(String.self, forKey: .statusRef)
            domains = try container.decodeIfPresent([String].self, forKey: .domains) ?? []
            handoffRefs = try container.decodeIfPresent([HandoffRef].self, forKey: .handoffRefs)
            retryRefs = try container.decodeIfPresent([RetryRef].self, forKey: .retryRefs)
            reviewItems = try container.decodeIfPresent([FlowRunReviewItem].self, forKey: .reviewItems) ?? []
            nextActions = try container.decodeIfPresent([FlowRunNextAction].self, forKey: .nextActions) ?? []
        }
    }

    public var schemaVersion: Int
    public var runID: String
    public var status: FlowRunStatus
    public var readiness: Readiness
    public var runDirectoryPath: String
    public var summary: Summary
    public var runArtifacts: [Artifact]
    public var stages: [Stage]
    public var runReviewItems: [FlowRunReviewItem]
    public var nextActions: [FlowRunNextAction]
    public var replayCommands: [FlowRunSuggestedCommand]
    public var signoffManifestCoverage: SignoffManifestCoverage?

    public init(
        schemaVersion: Int = 1,
        runID: String,
        status: FlowRunStatus,
        readiness: Readiness,
        runDirectoryPath: String,
        summary: Summary,
        runArtifacts: [Artifact] = [],
        stages: [Stage] = [],
        runReviewItems: [FlowRunReviewItem] = [],
        nextActions: [FlowRunNextAction] = [],
        replayCommands: [FlowRunSuggestedCommand] = [],
        signoffManifestCoverage: SignoffManifestCoverage? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.readiness = readiness
        self.runDirectoryPath = runDirectoryPath
        self.summary = summary
        self.runArtifacts = runArtifacts
        self.stages = stages
        self.runReviewItems = runReviewItems
        self.nextActions = nextActions
        self.replayCommands = replayCommands
        self.signoffManifestCoverage = signoffManifestCoverage
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case status
        case readiness
        case runDirectoryPath
        case summary
        case runArtifacts
        case stages
        case runReviewItems
        case nextActions
        case replayCommands
        case signoffManifestCoverage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        runID = try container.decode(String.self, forKey: .runID)
        status = try container.decode(FlowRunStatus.self, forKey: .status)
        readiness = try container.decodeIfPresent(Readiness.self, forKey: .readiness) ?? .needsReview
        runDirectoryPath = try container.decodeIfPresent(
            String.self,
            forKey: .runDirectoryPath
        ) ?? "\(XcircuitePackage.directoryName)/runs/\(runID)"
        summary = try container.decode(Summary.self, forKey: .summary)
        runArtifacts = try container.decodeIfPresent([Artifact].self, forKey: .runArtifacts) ?? []
        stages = try container.decodeIfPresent([Stage].self, forKey: .stages) ?? []
        runReviewItems = try container.decodeIfPresent([FlowRunReviewItem].self, forKey: .runReviewItems) ?? []
        nextActions = try container.decodeIfPresent([FlowRunNextAction].self, forKey: .nextActions) ?? []
        replayCommands = try container.decodeIfPresent([FlowRunSuggestedCommand].self, forKey: .replayCommands) ?? []
        signoffManifestCoverage = try container.decodeIfPresent(
            SignoffManifestCoverage.self,
            forKey: .signoffManifestCoverage
        )
    }
}

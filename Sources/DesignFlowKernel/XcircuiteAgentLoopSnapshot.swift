import CircuiteFoundation
import Foundation

public struct XcircuiteAgentLoopSnapshot: Sendable, Hashable, Codable {
    public struct BudgetUsage: Sendable, Hashable, Codable {
        public var actionCount: Int
        public var maxActions: Int?
        public var elapsedSeconds: Int?
        public var maxElapsedSeconds: Int?
        public var toolInvocationCount: Int
        public var maxToolInvocations: Int?
        public var changedFileCount: Int
        public var maxChangedFiles: Int?
        public var designChangeCount: Int
        public var maxDesignChanges: Int?
        public var exceededBudgetIDs: [String]

        public init(
            actionCount: Int,
            maxActions: Int? = nil,
            elapsedSeconds: Int? = nil,
            maxElapsedSeconds: Int? = nil,
            toolInvocationCount: Int,
            maxToolInvocations: Int? = nil,
            changedFileCount: Int,
            maxChangedFiles: Int? = nil,
            designChangeCount: Int,
            maxDesignChanges: Int? = nil,
            exceededBudgetIDs: [String] = []
        ) {
            self.actionCount = actionCount
            self.maxActions = maxActions
            self.elapsedSeconds = elapsedSeconds
            self.maxElapsedSeconds = maxElapsedSeconds
            self.toolInvocationCount = toolInvocationCount
            self.maxToolInvocations = maxToolInvocations
            self.changedFileCount = changedFileCount
            self.maxChangedFiles = maxChangedFiles
            self.designChangeCount = designChangeCount
            self.maxDesignChanges = maxDesignChanges
            self.exceededBudgetIDs = exceededBudgetIDs
        }
    }

    public struct EvidenceCoverage: Sendable, Hashable, Codable {
        public enum Status: String, Sendable, Hashable, Codable {
            case satisfied
            case missing
            case stale
            case optionalMissing
        }

        public struct Item: Sendable, Hashable, Codable {
            public var evidenceID: String
            public var artifactRole: String
            public var artifactID: String?
            public var stageID: String?
            public var status: Status
            public var artifactReferences: [ArtifactReference]
            public var reason: String?

            public init(
                evidenceID: String,
                artifactRole: String,
                artifactID: String? = nil,
                stageID: String? = nil,
                status: Status,
                artifactReferences: [ArtifactReference] = [],
                reason: String? = nil
            ) {
                self.evidenceID = evidenceID
                self.artifactRole = artifactRole
                self.artifactID = artifactID
                self.stageID = stageID
                self.status = status
                self.artifactReferences = artifactReferences
                self.reason = reason
            }

            private enum CodingKeys: String, CodingKey {
                case evidenceID
                case artifactRole
                case artifactID
                case stageID
                case status
                case artifactReferences
                case reason
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                evidenceID = try container.decode(String.self, forKey: .evidenceID)
                artifactRole = try container.decode(String.self, forKey: .artifactRole)
                artifactID = try container.decodeIfPresent(String.self, forKey: .artifactID)
                stageID = try container.decodeIfPresent(String.self, forKey: .stageID)
                status = try container.decode(Status.self, forKey: .status)
                do {
                    artifactReferences = try container.decode(
                        [ArtifactReference].self,
                        forKey: .artifactReferences
                    )
                } catch {
                    let legacy = try container.decode(
                        [XcircuiteFileReference].self,
                        forKey: .artifactReferences
                    )
                    artifactReferences = try legacy.map { try $0.foundationArtifactReference() }
                }
                reason = try container.decodeIfPresent(String.self, forKey: .reason)
            }
        }

        public var requiredCount: Int
        public var satisfiedCount: Int
        public var missingCount: Int
        public var staleCount: Int
        public var availableArtifactIDs: [String]
        public var items: [Item]

        public init(
            requiredCount: Int,
            satisfiedCount: Int,
            missingCount: Int,
            staleCount: Int,
            availableArtifactIDs: [String],
            items: [Item]
        ) {
            self.requiredCount = requiredCount
            self.satisfiedCount = satisfiedCount
            self.missingCount = missingCount
            self.staleCount = staleCount
            self.availableArtifactIDs = availableArtifactIDs
            self.items = items
        }
    }

    public struct MetricTrend: Sendable, Hashable, Codable {
        public var acceptedCount: Int
        public var rejectedCount: Int
        public var needsHumanReviewCount: Int
        public var blockedCount: Int
        public var inconclusiveCount: Int
        public var channelIDs: [String]

        public init(
            acceptedCount: Int = 0,
            rejectedCount: Int = 0,
            needsHumanReviewCount: Int = 0,
            blockedCount: Int = 0,
            inconclusiveCount: Int = 0,
            channelIDs: [String] = []
        ) {
            self.acceptedCount = acceptedCount
            self.rejectedCount = rejectedCount
            self.needsHumanReviewCount = needsHumanReviewCount
            self.blockedCount = blockedCount
            self.inconclusiveCount = inconclusiveCount
            self.channelIDs = channelIDs
        }
    }

    public struct DiagnosticTrend: Sendable, Hashable, Codable {
        public var diagnosticCount: Int
        public var failedDiagnosticCount: Int
        public var repeatedCodes: [String: Int]
        public var newestCodes: [String]

        public init(
            diagnosticCount: Int = 0,
            failedDiagnosticCount: Int = 0,
            repeatedCodes: [String: Int] = [:],
            newestCodes: [String] = []
        ) {
            self.diagnosticCount = diagnosticCount
            self.failedDiagnosticCount = failedDiagnosticCount
            self.repeatedCodes = repeatedCodes
            self.newestCodes = newestCodes
        }
    }

    public struct ApprovalState: Sendable, Hashable, Codable {
        public enum Status: String, Sendable, Hashable, Codable {
            case notRequired
            case pending
            case approved
            case rejected
        }

        public var status: Status
        public var pendingStageIDs: [String]
        public var approvedStageIDs: [String]
        public var rejectedStageIDs: [String]

        public init(
            status: Status,
            pendingStageIDs: [String] = [],
            approvedStageIDs: [String] = [],
            rejectedStageIDs: [String] = []
        ) {
            self.status = status
            self.pendingStageIDs = pendingStageIDs
            self.approvedStageIDs = approvedStageIDs
            self.rejectedStageIDs = rejectedStageIDs
        }
    }

    public struct ResumeReadiness: Sendable, Hashable, Codable {
        public enum Status: String, Sendable, Hashable, Codable {
            case ready
            case needsHumanReview
            case blocked
        }

        public var status: Status
        public var reasons: [String]

        public init(status: Status, reasons: [String] = []) {
            self.status = status
            self.reasons = reasons
        }
    }

    public var schemaVersion: Int
    public var snapshotID: String
    public var runID: String
    public var profileID: String
    public var latestIterationID: String?
    public var generatedAt: Date
    public var actionCount: Int
    public var artifactCount: Int
    public var budgetUsage: BudgetUsage
    public var evidenceCoverage: EvidenceCoverage
    public var metricTrend: MetricTrend
    public var diagnosticTrend: DiagnosticTrend
    public var approvalState: ApprovalState
    public var resumeReadiness: ResumeReadiness
    public var metadata: [String: XcircuiteJSONValue]

    public init(
        schemaVersion: Int = 1,
        snapshotID: String,
        runID: String,
        profileID: String,
        latestIterationID: String? = nil,
        generatedAt: Date = Date(),
        actionCount: Int,
        artifactCount: Int,
        budgetUsage: BudgetUsage,
        evidenceCoverage: EvidenceCoverage,
        metricTrend: MetricTrend = MetricTrend(),
        diagnosticTrend: DiagnosticTrend = DiagnosticTrend(),
        approvalState: ApprovalState,
        resumeReadiness: ResumeReadiness,
        metadata: [String: XcircuiteJSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.snapshotID = snapshotID
        self.runID = runID
        self.profileID = profileID
        self.latestIterationID = latestIterationID
        self.generatedAt = generatedAt
        self.actionCount = actionCount
        self.artifactCount = artifactCount
        self.budgetUsage = budgetUsage
        self.evidenceCoverage = evidenceCoverage
        self.metricTrend = metricTrend
        self.diagnosticTrend = diagnosticTrend
        self.approvalState = approvalState
        self.resumeReadiness = resumeReadiness
        self.metadata = metadata
    }
}

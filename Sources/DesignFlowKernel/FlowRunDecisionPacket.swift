import Foundation

public struct FlowRunDecisionPacket: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 3

    public enum Readiness: String, Sendable, Hashable, Codable {
        case ready
        case needsReview
        case blocked
    }

    public enum ArtifactRequirementStatus: String, Sendable, Hashable, Codable {
        case satisfied
        case missing
        case invalid
        case notRequired
    }

    public struct ArtifactRequirement: Sendable, Hashable, Codable {
        public var role: String
        public var required: Bool
        public var status: ArtifactRequirementStatus
        public var purpose: String
        public var artifactPaths: [String]
        public var diagnosticCodes: [String]

        public init(
            role: String,
            required: Bool,
            status: ArtifactRequirementStatus,
            purpose: String,
            artifactPaths: [String] = [],
            diagnosticCodes: [String] = []
        ) {
            self.role = role
            self.required = required
            self.status = status
            self.purpose = purpose
            self.artifactPaths = artifactPaths
            self.diagnosticCodes = diagnosticCodes
        }
    }

    public struct CompletionIssue: Sendable, Hashable, Codable {
        public var code: String
        public var severity: FlowDiagnosticSeverity
        public var message: String
        public var artifactRole: String?
        public var reviewItemID: String?
        public var nextActionID: String?
        public var artifactPaths: [String]

        public init(
            code: String,
            severity: FlowDiagnosticSeverity,
            message: String,
            artifactRole: String? = nil,
            reviewItemID: String? = nil,
            nextActionID: String? = nil,
            artifactPaths: [String] = []
        ) {
            self.code = code
            self.severity = severity
            self.message = message
            self.artifactRole = artifactRole
            self.reviewItemID = reviewItemID
            self.nextActionID = nextActionID
            self.artifactPaths = artifactPaths
        }
    }

    public let schemaVersion: Int
    public var packetID: String
    public var runID: String
    public var status: FlowRunStatus
    public var readiness: Readiness
    public var reviewBundle: FlowRunReviewBundle
    public var requiredArtifacts: [ArtifactRequirement]
    public var unresolvedReviewItems: [FlowRunReviewItem]
    public var completionIssues: [CompletionIssue]
    public var replayActions: [FlowRunSuggestedAction]

    public init(
        packetID: String,
        runID: String,
        status: FlowRunStatus,
        readiness: Readiness,
        reviewBundle: FlowRunReviewBundle,
        requiredArtifacts: [ArtifactRequirement],
        unresolvedReviewItems: [FlowRunReviewItem],
        completionIssues: [CompletionIssue],
        replayActions: [FlowRunSuggestedAction]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.packetID = packetID
        self.runID = runID
        self.status = status
        self.readiness = readiness
        self.reviewBundle = reviewBundle
        self.requiredArtifacts = requiredArtifacts
        self.unresolvedReviewItems = unresolvedReviewItems
        self.completionIssues = completionIssues
        self.replayActions = replayActions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case packetID
        case runID
        case status
        case readiness
        case reviewBundle
        case requiredArtifacts
        case unresolvedReviewItems
        case completionIssues
        case replayActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected decision packet schema version \(Self.currentSchemaVersion)."
            )
        }
        packetID = try container.decode(String.self, forKey: .packetID)
        runID = try container.decode(String.self, forKey: .runID)
        status = try container.decode(FlowRunStatus.self, forKey: .status)
        readiness = try container.decode(Readiness.self, forKey: .readiness)
        reviewBundle = try container.decode(FlowRunReviewBundle.self, forKey: .reviewBundle)
        requiredArtifacts = try container.decode([ArtifactRequirement].self, forKey: .requiredArtifacts)
        unresolvedReviewItems = try container.decode([FlowRunReviewItem].self, forKey: .unresolvedReviewItems)
        completionIssues = try container.decode([CompletionIssue].self, forKey: .completionIssues)
        replayActions = try container.decode([FlowRunSuggestedAction].self, forKey: .replayActions)
    }
}

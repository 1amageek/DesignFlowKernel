import Foundation

public struct FlowEvaluationProfile: Sendable, Hashable, Codable {
    public struct MetricChannel: Sendable, Hashable, Codable {
        public enum Direction: String, Sendable, Hashable, Codable {
            case maximize
            case minimize
            case target
            case bounded
            case categorical
        }

        public var channelID: String
        public var label: String?
        public var unit: String?
        public var direction: Direction
        public var target: FlowMetricValue?
        public var tolerance: Double?
        public var required: Bool
        public var context: FlowEvaluationContext?

        public init(
            channelID: String,
            label: String? = nil,
            unit: String? = nil,
            direction: Direction,
            target: FlowMetricValue? = nil,
            tolerance: Double? = nil,
            required: Bool = true,
            context: FlowEvaluationContext? = nil
        ) {
            self.channelID = channelID
            self.label = label
            self.unit = unit
            self.direction = direction
            self.target = target
            self.tolerance = tolerance
            self.required = required
            self.context = context
        }
    }

    public struct RequiredAnalysis: Sendable, Hashable, Codable {
        public var analysisID: String
        public var domain: String
        public var artifactRole: String
        public var required: Bool

        public init(
            analysisID: String,
            domain: String,
            artifactRole: String,
            required: Bool = true
        ) {
            self.analysisID = analysisID
            self.domain = domain
            self.artifactRole = artifactRole
            self.required = required
        }
    }

    public struct ArtifactRole: Sendable, Hashable, Codable {
        public var role: String
        public var required: Bool
        public var description: String?

        public init(role: String, required: Bool = true, description: String? = nil) {
            self.role = role
            self.required = required
            self.description = description
        }
    }

    public enum ComparisonPolicy: String, Sendable, Hashable, Codable {
        case baseline
        case previousIteration
        case golden
        case target
    }

    @FlowSchemaVersion1 public var schemaVersion: Int
    public var profileID: String
    public var domain: String
    public var metricChannels: [MetricChannel]
    public var requiredAnalyses: [RequiredAnalysis]
    public var artifactRoles: [ArtifactRole]
    public var comparisonPolicy: ComparisonPolicy

    public init(
        schemaVersion: Int = 1,
        profileID: String,
        domain: String,
        metricChannels: [MetricChannel] = [],
        requiredAnalyses: [RequiredAnalysis] = [],
        artifactRoles: [ArtifactRole] = [],
        comparisonPolicy: ComparisonPolicy = .previousIteration
    ) {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.domain = domain
        self.metricChannels = metricChannels
        self.requiredAnalyses = requiredAnalyses
        self.artifactRoles = artifactRoles
        self.comparisonPolicy = comparisonPolicy
    }
}

import Foundation

public struct FlowRunSignoffDashboard: Sendable, Hashable, Decodable {
    public struct Failure: Sendable, Hashable, Decodable {}

    public struct Measurement: Sendable, Hashable, Decodable {
        public var status: String?
        public var qualified: Bool?
        public var caseCount: Double?
        public var passRate: Double?
        public var totalDurationSeconds: Double?
        public var coverageTagCount: Double?
    }

    public struct Baseline: Sendable, Hashable, Decodable {
        public var medianPassRate: Double?
        public var medianTotalDurationSeconds: Double?
        public var maxAllowedTotalDurationSeconds: Double?
    }

    public struct Domain: Sendable, Hashable, Decodable {
        public var domain: String
        public var status: String?
        public var previousQualifiedEntryCount: Int?
        public var current: Measurement?
        public var baseline: Baseline?
        public var durationRegressionRatio: Double?
        public var failures: [Failure]?
    }

    public struct Promotion: Sendable, Hashable, Decodable {
        public var status: String
        public var failures: [Failure]
    }

    public struct Entry: Sendable, Hashable, Decodable {
        public var recordedAt: String?
    }

    public struct History: Sendable, Hashable, Decodable {
        public var status: String
        public var previousEntryCount: Int?
        public var maxTotalDurationRegression: Double?
        public var appended: Bool?
        public var domains: [Domain]?
        public var promotion: Promotion?
        public var failures: [Failure]?
        public var entry: Entry?
    }

    public struct RetainedSignoffSuite: Sendable, Hashable, Decodable {
        public var status: String
    }

    public var schemaVersion: Int
    public var runID: String?
    public var status: String
    public var history: History
    public var retainedSignoffSuite: RetainedSignoffSuite
}

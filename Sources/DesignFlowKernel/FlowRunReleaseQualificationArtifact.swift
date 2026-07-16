import Foundation

public struct FlowRunReleaseQualificationArtifact: Sendable, Hashable, Decodable {
    public struct Metadata: Sendable, Hashable, Decodable {
        public var completedAt: String?
    }

    public struct Diagnostic: Sendable, Hashable, Decodable {
        public var severity: String
    }

    public struct Scope: Sendable, Hashable, Decodable {
        public var implementationID: String
        public var binaryDigest: String
        public var algorithmVersion: String
        public var processProfileID: String
        public var deckDigest: String
    }

    public struct Lane: Sendable, Hashable, Decodable {
        public var status: String
        public var qualified: Bool
        public var failureCodes: [String]
    }

    public struct Payload: Sendable, Hashable, Decodable {
        public var qualified: Bool
        public var promotionStatus: String?
        public var qualificationDigest: String?
        public var promotionFailureCodes: [String]?
        public var blockedLanes: [String]?
        public var failedLanes: [String]?
        public var qualificationScope: Scope?
        public var laneResults: [Lane]?
    }

    public var runID: String?
    public var status: String
    public var metadata: Metadata?
    public var payload: Payload?
    public var diagnostics: [Diagnostic]?
}

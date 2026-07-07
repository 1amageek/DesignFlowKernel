import Foundation

public struct FlowRunStageSummary: Sendable, Hashable, Codable {
    public var stageID: String
    public var status: FlowStageStatus
    public var gates: [FlowRunGateSummary]
    public var diagnosticCodes: [String]
    public var artifactCount: Int
    public var attemptCount: Int
    public var retryCount: Int

    public init(
        stageID: String,
        status: FlowStageStatus,
        gates: [FlowRunGateSummary] = [],
        diagnosticCodes: [String] = [],
        artifactCount: Int = 0,
        attemptCount: Int = 0,
        retryCount: Int = 0
    ) {
        self.stageID = stageID
        self.status = status
        self.gates = gates
        self.diagnosticCodes = diagnosticCodes
        self.artifactCount = artifactCount
        self.attemptCount = attemptCount
        self.retryCount = retryCount
    }

    private enum CodingKeys: String, CodingKey {
        case stageID
        case status
        case gates
        case diagnosticCodes
        case artifactCount
        case attemptCount
        case retryCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stageID = try container.decode(String.self, forKey: .stageID)
        status = try container.decode(FlowStageStatus.self, forKey: .status)
        gates = try container.decodeIfPresent([FlowRunGateSummary].self, forKey: .gates) ?? []
        diagnosticCodes = try container.decodeIfPresent([String].self, forKey: .diagnosticCodes) ?? []
        artifactCount = try container.decodeIfPresent(Int.self, forKey: .artifactCount) ?? 0
        attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
    }
}

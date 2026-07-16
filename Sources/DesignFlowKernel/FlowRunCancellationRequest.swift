import Foundation

public struct FlowRunCancellationRequest: Sendable, Hashable, Codable {
    @FlowSchemaVersion1 public var schemaVersion: Int
    public var runID: String
    public var requestedBy: String
    public var reason: String
    public var requestedAt: Date

    public init(
        schemaVersion: Int = 1,
        runID: String,
        requestedBy: String,
        reason: String,
        requestedAt: Date = Date()
    ) throws {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.requestedBy = requestedBy
        self.reason = reason
        self.requestedAt = requestedAt
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case requestedBy
        case reason
        case requestedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(String.self, forKey: .runID)
        requestedBy = try container.decode(String.self, forKey: .requestedBy)
        reason = try container.decode(String.self, forKey: .reason)
        requestedAt = try container.decode(Date.self, forKey: .requestedAt)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(runID, forKey: .runID)
        try container.encode(requestedBy, forKey: .requestedBy)
        try container.encode(reason, forKey: .reason)
        try container.encode(requestedAt, forKey: .requestedAt)
    }

    private func validate() throws {
        guard schemaVersion == FlowSchemaVersion1.currentValue else {
            throw FlowRunCancellationRequestError.invalidSchemaVersion(schemaVersion)
        }
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        guard !requestedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FlowRunCancellationRequestError.emptyRequestedBy
        }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FlowRunCancellationRequestError.emptyReason
        }
    }
}

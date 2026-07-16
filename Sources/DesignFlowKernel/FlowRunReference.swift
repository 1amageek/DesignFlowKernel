import Foundation

public struct FlowRunReference: Sendable, Hashable, Codable {
    public var runID: String
    public var manifestPath: String

    public init(
        runID: String,
        manifestPath: String
    ) {
        self.runID = runID
        self.manifestPath = manifestPath
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case manifestPath
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard !container.contains(.status) else {
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Run status belongs only in the canonical run manifest."
            )
        }
        runID = try container.decode(String.self, forKey: .runID)
        manifestPath = try container.decode(String.self, forKey: .manifestPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runID, forKey: .runID)
        try container.encode(manifestPath, forKey: .manifestPath)
    }
}

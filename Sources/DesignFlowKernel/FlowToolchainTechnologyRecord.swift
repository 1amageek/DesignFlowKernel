import Foundation

public enum FlowToolchainTechnologyRecord: Sendable, Hashable, Codable {
    case jsonFile(path: String)
    case input(FlowToolchainInputReferenceRecord)
    case inline(FlowToolchainInlineTechnologyRecord)

    private enum CodingKeys: String, CodingKey {
        case type
        case path
        case value
    }

    private enum Kind: String, Codable {
        case jsonFile
        case input
        case inline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .jsonFile:
            self = .jsonFile(path: try container.decode(String.self, forKey: .path))
        case .input:
            self = .input(try container.decode(FlowToolchainInputReferenceRecord.self, forKey: .value))
        case .inline:
            self = .inline(try container.decode(FlowToolchainInlineTechnologyRecord.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .jsonFile(let path):
            try container.encode(Kind.jsonFile, forKey: .type)
            try container.encode(path, forKey: .path)
        case .input(let input):
            try container.encode(Kind.input, forKey: .type)
            try container.encode(input, forKey: .value)
        case .inline(let technology):
            try container.encode(Kind.inline, forKey: .type)
            try container.encode(technology, forKey: .value)
        }
    }
}

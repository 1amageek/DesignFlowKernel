import Foundation
import CircuiteFoundation

public enum FlowToolchainInputReferenceRecord: Sendable, Hashable, Codable {
    case path(String)
    /// Canonical artifact input.
    case artifact(ArtifactReference)
    case stageArtifact(FlowToolchainStageArtifactSelectorRecord)
    case stageRawArtifact(FlowToolchainStageRawArtifactRecord)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case path
        case artifact
        case stageArtifact
        case stageRawArtifact
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .path:
            self = .path(try container.decode(String.self, forKey: .value))
        case .artifact:
            self = .artifact(try container.decode(ArtifactReference.self, forKey: .value))
        case .stageArtifact:
            self = .stageArtifact(
                try container.decode(FlowToolchainStageArtifactSelectorRecord.self, forKey: .value)
            )
        case .stageRawArtifact:
            self = .stageRawArtifact(
                try container.decode(FlowToolchainStageRawArtifactRecord.self, forKey: .value)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .path(let path):
            try container.encode(Kind.path, forKey: .kind)
            try container.encode(path, forKey: .value)
        case .artifact(let artifact):
            try container.encode(Kind.artifact, forKey: .kind)
            try container.encode(artifact, forKey: .value)
        case .stageArtifact(let artifact):
            try container.encode(Kind.stageArtifact, forKey: .kind)
            try container.encode(artifact, forKey: .value)
        case .stageRawArtifact(let artifact):
            try container.encode(Kind.stageRawArtifact, forKey: .kind)
            try container.encode(artifact, forKey: .value)
        }
    }
}

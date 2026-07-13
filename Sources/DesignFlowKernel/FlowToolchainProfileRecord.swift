import Foundation

public struct FlowToolchainProfileRecord: Sendable, Hashable, Codable {
    public var profileID: String?
    public var pdkID: String?
    public var technologyCatalogID: String?
    public var technologyCatalogPath: String?
    public var profileArtifactPath: String?
    public var drcTechnologyInput: FlowToolchainInputReferenceRecord?
    public var lvsTechnologyInput: FlowToolchainInputReferenceRecord?
    public var pexTechnology: FlowToolchainTechnologyRecord?
    public var pexTechnologyByCorner: [String: FlowToolchainTechnologyRecord]
    public var metadata: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case profileID
        case pdkID
        case technologyCatalogID
        case technologyCatalogPath
        case profileArtifactPath
        case drcTechnologyInput
        case lvsTechnologyInput
        case pexTechnology
        case pexTechnologyByCorner
        case metadata
    }

    public init(
        profileID: String? = nil,
        pdkID: String? = nil,
        technologyCatalogID: String? = nil,
        technologyCatalogPath: String? = nil,
        profileArtifactPath: String? = nil,
        drcTechnologyInput: FlowToolchainInputReferenceRecord? = nil,
        lvsTechnologyInput: FlowToolchainInputReferenceRecord? = nil,
        pexTechnology: FlowToolchainTechnologyRecord? = nil,
        pexTechnologyByCorner: [String: FlowToolchainTechnologyRecord] = [:],
        metadata: [String: String]? = nil
    ) {
        self.profileID = profileID
        self.pdkID = pdkID
        self.technologyCatalogID = technologyCatalogID
        self.technologyCatalogPath = technologyCatalogPath
        self.profileArtifactPath = profileArtifactPath
        self.drcTechnologyInput = drcTechnologyInput
        self.lvsTechnologyInput = lvsTechnologyInput
        self.pexTechnology = pexTechnology
        self.pexTechnologyByCorner = pexTechnologyByCorner
        self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileID = try container.decodeIfPresent(String.self, forKey: .profileID)
        pdkID = try container.decodeIfPresent(String.self, forKey: .pdkID)
        technologyCatalogID = try container.decodeIfPresent(String.self, forKey: .technologyCatalogID)
        technologyCatalogPath = try container.decodeIfPresent(String.self, forKey: .technologyCatalogPath)
        profileArtifactPath = try container.decodeIfPresent(String.self, forKey: .profileArtifactPath)
        drcTechnologyInput = try container.decodeIfPresent(
            FlowToolchainInputReferenceRecord.self,
            forKey: .drcTechnologyInput
        )
        lvsTechnologyInput = try container.decodeIfPresent(
            FlowToolchainInputReferenceRecord.self,
            forKey: .lvsTechnologyInput
        )
        pexTechnology = try container.decodeIfPresent(
            FlowToolchainTechnologyRecord.self,
            forKey: .pexTechnology
        )
        pexTechnologyByCorner = try container.decodeIfPresent(
            [String: FlowToolchainTechnologyRecord].self,
            forKey: .pexTechnologyByCorner
        ) ?? [:]
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(profileID, forKey: .profileID)
        try container.encodeIfPresent(pdkID, forKey: .pdkID)
        try container.encodeIfPresent(technologyCatalogID, forKey: .technologyCatalogID)
        try container.encodeIfPresent(technologyCatalogPath, forKey: .technologyCatalogPath)
        try container.encodeIfPresent(profileArtifactPath, forKey: .profileArtifactPath)
        try container.encodeIfPresent(drcTechnologyInput, forKey: .drcTechnologyInput)
        try container.encodeIfPresent(lvsTechnologyInput, forKey: .lvsTechnologyInput)
        try container.encodeIfPresent(pexTechnology, forKey: .pexTechnology)
        try container.encode(pexTechnologyByCorner, forKey: .pexTechnologyByCorner)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

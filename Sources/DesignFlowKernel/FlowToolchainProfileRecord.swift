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
    public var metadata: [String: String]?

    public init(
        profileID: String? = nil,
        pdkID: String? = nil,
        technologyCatalogID: String? = nil,
        technologyCatalogPath: String? = nil,
        profileArtifactPath: String? = nil,
        drcTechnologyInput: FlowToolchainInputReferenceRecord? = nil,
        lvsTechnologyInput: FlowToolchainInputReferenceRecord? = nil,
        pexTechnology: FlowToolchainTechnologyRecord? = nil,
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
        self.metadata = metadata
    }
}

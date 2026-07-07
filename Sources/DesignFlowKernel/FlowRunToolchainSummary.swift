import Foundation

public struct FlowRunToolchainSummary: Sendable, Hashable, Codable {
    public var stageCount: Int
    public var selectedToolIDs: [String]
    public var rejectedEvaluationCount: Int
    public var missingSelectionStageIDs: [String]
    public var profileID: String?
    public var pdkID: String?
    public var technologyCatalogID: String?
    public var technologyCatalogPath: String?
    public var profileArtifactPath: String?

    public init(
        stageCount: Int,
        selectedToolIDs: [String] = [],
        rejectedEvaluationCount: Int = 0,
        missingSelectionStageIDs: [String] = [],
        profileID: String? = nil,
        pdkID: String? = nil,
        technologyCatalogID: String? = nil,
        technologyCatalogPath: String? = nil,
        profileArtifactPath: String? = nil
    ) {
        self.stageCount = stageCount
        self.selectedToolIDs = selectedToolIDs
        self.rejectedEvaluationCount = rejectedEvaluationCount
        self.missingSelectionStageIDs = missingSelectionStageIDs
        self.profileID = profileID
        self.pdkID = pdkID
        self.technologyCatalogID = technologyCatalogID
        self.technologyCatalogPath = technologyCatalogPath
        self.profileArtifactPath = profileArtifactPath
    }
}

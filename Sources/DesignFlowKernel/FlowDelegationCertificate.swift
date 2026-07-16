import Foundation

public struct FlowDelegationCertificate: Sendable, Hashable, Codable {
    public var certificateID: String
    public var issuedBy: String
    public var issuedTo: String
    public var scope: String
    public var artifactIDs: [String]
    public var issuedAt: String?

    public init(
        certificateID: String,
        issuedBy: String,
        issuedTo: String,
        scope: String,
        artifactIDs: [String] = [],
        issuedAt: String? = nil
    ) {
        self.certificateID = certificateID
        self.issuedBy = issuedBy
        self.issuedTo = issuedTo
        self.scope = scope
        self.artifactIDs = artifactIDs
        self.issuedAt = issuedAt
    }
}

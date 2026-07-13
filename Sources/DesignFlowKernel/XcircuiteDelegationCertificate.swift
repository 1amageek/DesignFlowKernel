import Foundation

public struct XcircuiteDelegationCertificate: Sendable, Hashable, Codable {
    public var certificateID: String
    public var issuedBy: String
    public var issuedTo: String
    public var scope: String
    public var artifactIDs: [String]
    public var issuedAt: String?
    public var metadata: [String: XcircuiteJSONValue]

    public init(
        certificateID: String,
        issuedBy: String,
        issuedTo: String,
        scope: String,
        artifactIDs: [String] = [],
        issuedAt: String? = nil,
        metadata: [String: XcircuiteJSONValue] = [:]
    ) {
        self.certificateID = certificateID
        self.issuedBy = issuedBy
        self.issuedTo = issuedTo
        self.scope = scope
        self.artifactIDs = artifactIDs
        self.issuedAt = issuedAt
        self.metadata = metadata
    }
}

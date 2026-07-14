import Foundation

public struct XcircuiteFileReference: Sendable, Hashable, Codable {
    public var artifactID: String?
    public var path: String
    public var kind: XcircuiteFileKind
    public var format: XcircuiteFileFormat
    public var sha256: String?
    public var byteCount: Int64?
    public var producedByRunID: String?
    public var verifiedByRunID: String?

    public init(
        artifactID: String? = nil,
        path: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        sha256: String? = nil,
        byteCount: Int64? = nil,
        producedByRunID: String? = nil,
        verifiedByRunID: String? = nil
    ) {
        self.artifactID = artifactID
        self.path = path
        self.kind = kind
        self.format = format
        self.sha256 = sha256
        self.byteCount = byteCount
        self.producedByRunID = producedByRunID
        self.verifiedByRunID = verifiedByRunID
    }
}

import Foundation
import XcircuitePackage

public struct FlowRunReviewArtifact: Sendable, Hashable, Codable {
    public var role: String
    public var artifactID: String?
    public var stageID: String?
    public var path: String
    public var kind: XcircuiteFileKind
    public var format: XcircuiteFileFormat
    public var sha256: String?
    public var byteCount: Int64?
    public var integrity: FlowRunReviewArtifactIntegrity?

    public init(
        role: String,
        artifactID: String? = nil,
        stageID: String? = nil,
        path: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        sha256: String? = nil,
        byteCount: Int64? = nil,
        integrity: FlowRunReviewArtifactIntegrity? = nil
    ) {
        self.role = role
        self.artifactID = artifactID
        self.stageID = stageID
        self.path = path
        self.kind = kind
        self.format = format
        self.sha256 = sha256
        self.byteCount = byteCount
        self.integrity = integrity
    }
}

import Foundation
import CircuiteFoundation

public struct FlowRunReviewArtifact: Sendable, Hashable, Codable {
    public var role: String
    public var artifactID: String?
    public var stageID: String?
    public var path: String
    public var kind: ArtifactKind
    public var format: ArtifactFormat
    public var sha256: String?
    public var byteCount: UInt64?
    public var integrity: FlowRunReviewArtifactIntegrity?

    public init(
        role: String,
        artifactID: String? = nil,
        stageID: String? = nil,
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        sha256: String? = nil,
        byteCount: UInt64? = nil,
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

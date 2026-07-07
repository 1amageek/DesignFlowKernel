import Foundation

public struct FlowRunReviewArtifactIntegrity: Sendable, Hashable, Codable {
    public var status: FlowRunReviewArtifactIntegrityStatus
    public var expectedSHA256: String?
    public var actualSHA256: String?
    public var expectedByteCount: Int64?
    public var actualByteCount: Int64?
    public var message: String

    public init(
        status: FlowRunReviewArtifactIntegrityStatus,
        expectedSHA256: String? = nil,
        actualSHA256: String? = nil,
        expectedByteCount: Int64? = nil,
        actualByteCount: Int64? = nil,
        message: String
    ) {
        self.status = status
        self.expectedSHA256 = expectedSHA256
        self.actualSHA256 = actualSHA256
        self.expectedByteCount = expectedByteCount
        self.actualByteCount = actualByteCount
        self.message = message
    }
}

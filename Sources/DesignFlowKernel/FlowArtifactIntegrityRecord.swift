import Foundation

public struct FlowArtifactIntegrityRecord: Sendable, Hashable, Codable {
    public var status: FlowArtifactVerificationStatus
    public var path: String
    public var expectedSHA256: String?
    public var actualSHA256: String?
    public var expectedByteCount: UInt64?
    public var actualByteCount: UInt64?
    public var message: String

    public init(
        status: FlowArtifactVerificationStatus,
        path: String,
        expectedSHA256: String? = nil,
        actualSHA256: String? = nil,
        expectedByteCount: UInt64? = nil,
        actualByteCount: UInt64? = nil,
        message: String
    ) {
        self.status = status
        self.path = path
        self.expectedSHA256 = expectedSHA256
        self.actualSHA256 = actualSHA256
        self.expectedByteCount = expectedByteCount
        self.actualByteCount = actualByteCount
        self.message = message
    }
}

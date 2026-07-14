import Foundation

public struct XcircuiteFileReferenceVerifier: Sendable {
    private let hasher: XcircuiteHasher

    public init(
        hasher: XcircuiteHasher = XcircuiteHasher()
    ) {
        self.hasher = hasher
    }

    public func verify(
        _ reference: XcircuiteFileReference,
        projectRoot: URL
    ) -> XcircuiteFileReferenceIntegrity {
        guard let artifactURL = resolvedURL(for: reference, projectRoot: projectRoot) else {
            return XcircuiteFileReferenceIntegrity(
                status: .invalidPath,
                path: reference.path,
                expectedSHA256: reference.sha256,
                expectedByteCount: reference.byteCount,
                message: "Artifact path must be project-relative and stay inside the project root."
            )
        }

        let artifactPath = artifactURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: artifactPath) else {
            return XcircuiteFileReferenceIntegrity(
                status: .missingArtifact,
                path: reference.path,
                expectedSHA256: reference.sha256,
                expectedByteCount: reference.byteCount,
                message: "Artifact file is missing."
            )
        }

        guard let expectedSHA256 = reference.sha256, !expectedSHA256.isEmpty else {
            return XcircuiteFileReferenceIntegrity(
                status: .missingDigest,
                path: reference.path,
                expectedByteCount: reference.byteCount,
                message: "Artifact file exists but the file reference does not record a SHA-256 digest."
            )
        }
        guard isValidSHA256(expectedSHA256) else {
            return XcircuiteFileReferenceIntegrity(
                status: .invalidDigest,
                path: reference.path,
                expectedSHA256: expectedSHA256,
                expectedByteCount: reference.byteCount,
                message: "Artifact SHA-256 digest is not a 64-character hexadecimal value."
            )
        }
        guard let expectedByteCount = reference.byteCount else {
            return XcircuiteFileReferenceIntegrity(
                status: .missingByteCount,
                path: reference.path,
                expectedSHA256: expectedSHA256,
                message: "Artifact file exists but the file reference does not record a byte count."
            )
        }
        guard expectedByteCount >= 0 else {
            return XcircuiteFileReferenceIntegrity(
                status: .invalidByteCount,
                path: reference.path,
                expectedSHA256: expectedSHA256,
                expectedByteCount: expectedByteCount,
                message: "Artifact byte count must be non-negative."
            )
        }

        let actualSHA256: String
        let actualByteCount: Int64
        do {
            actualByteCount = try hasher.byteCount(fileAt: artifactURL)
            actualSHA256 = try hasher.sha256(fileAt: artifactURL)
        } catch {
            return XcircuiteFileReferenceIntegrity(
                status: .unreadableArtifact,
                path: reference.path,
                expectedSHA256: expectedSHA256,
                expectedByteCount: expectedByteCount,
                message: "Artifact file could not be read for integrity verification: \(error.localizedDescription)"
            )
        }

        guard actualByteCount == expectedByteCount else {
            return XcircuiteFileReferenceIntegrity(
                status: .byteCountMismatch,
                path: reference.path,
                expectedSHA256: expectedSHA256,
                actualSHA256: actualSHA256,
                expectedByteCount: expectedByteCount,
                actualByteCount: actualByteCount,
                message: "Artifact byte count does not match the file reference."
            )
        }
        guard actualSHA256 == expectedSHA256 else {
            return XcircuiteFileReferenceIntegrity(
                status: .sha256Mismatch,
                path: reference.path,
                expectedSHA256: expectedSHA256,
                actualSHA256: actualSHA256,
                expectedByteCount: expectedByteCount,
                actualByteCount: actualByteCount,
                message: "Artifact SHA-256 digest does not match the file reference."
            )
        }

        return XcircuiteFileReferenceIntegrity(
            status: .verified,
            path: reference.path,
            expectedSHA256: expectedSHA256,
            actualSHA256: actualSHA256,
            expectedByteCount: expectedByteCount,
            actualByteCount: actualByteCount,
            message: "Artifact file exists and matches the recorded SHA-256 digest and byte count."
        )
    }

    public func resolvedURL(
        for reference: XcircuiteFileReference,
        projectRoot: URL
    ) -> URL? {
        do {
            return try XcircuiteWorkspace(projectRoot: projectRoot)
                .url(forProjectRelativePath: reference.path)
        } catch {
            return nil
        }
    }

    private func isValidSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }

}

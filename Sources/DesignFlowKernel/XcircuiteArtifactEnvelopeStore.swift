import Foundation

extension XcircuitePackageStore {
    @discardableResult
    public func writeArtifactEnvelope(
        _ envelope: XcircuiteArtifactEnvelope,
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        try XcircuiteArtifactEnvelopeValidator().validate(envelope)
        try verifyArtifactEnvelopeReference(envelope.reference, projectRoot: projectRoot)

        let package = XcircuitePackage(projectRoot: projectRoot)
        let runDirectory = try ensureArtifactEnvelopeRunDirectory(
            runID: runID,
            package: package,
            projectRoot: projectRoot
        )
        let evidenceDirectory = runDirectory.appending(path: "evidence")
        try ensureDirectory(at: evidenceDirectory)

        let relativePath = artifactEnvelopeRelativePath(
            artifactID: envelope.artifactID,
            runID: runID
        )
        let envelopeURL = projectRoot.appending(path: relativePath)
        try writeJSON(envelope, to: envelopeURL, forProjectAt: projectRoot)

        let reference = try fileReference(
            forProjectRelativePath: relativePath,
            artifactID: artifactEnvelopeReferenceID(for: envelope.artifactID),
            kind: .report,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    public func loadArtifactEnvelope(
        artifactID: String,
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteArtifactEnvelope {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(artifactID, kind: .artifactID)

        let relativePath = artifactEnvelopeRelativePath(
            artifactID: artifactID,
            runID: runID
        )
        let envelopeURL = try url(
            forProjectRelativePath: relativePath,
            inProjectAt: projectRoot
        )
        let envelope = try readJSON(XcircuiteArtifactEnvelope.self, from: envelopeURL)
        try XcircuiteArtifactEnvelopeValidator().validate(envelope)
        try verifyArtifactEnvelopeReference(envelope.reference, projectRoot: projectRoot)
        return envelope
    }

    private func artifactEnvelopeRelativePath(
        artifactID: String,
        runID: String
    ) -> String {
        "\(XcircuitePackage.directoryName)/runs/\(runID)/evidence/\(artifactID)-envelope.json"
    }

    private func artifactEnvelopeReferenceID(for artifactID: String) -> String {
        let digest = String(
            XcircuiteHasher()
                .sha256(data: Data(artifactID.utf8))
                .prefix(16)
        )
        let prefix = "evidence-"
        let separator = "-"
        let maximumLength = 128
        let maximumArtifactPrefixLength = maximumLength - prefix.count - separator.count - digest.count
        let artifactPrefix = String(artifactID.prefix(maximumArtifactPrefixLength))
        return "\(prefix)\(artifactPrefix)\(separator)\(digest)"
    }

    private func verifyArtifactEnvelopeReference(
        _ reference: XcircuiteFileReference,
        projectRoot: URL
    ) throws {
        let integrity = XcircuiteFileReferenceVerifier().verify(
            reference,
            projectRoot: projectRoot
        )
        guard integrity.status == .verified else {
            throw XcircuiteArtifactEnvelopeValidationError.referenceIntegrityFailed(
                path: reference.path,
                status: integrity.status,
                message: integrity.message
            )
        }
    }

    private func ensureArtifactEnvelopeRunDirectory(
        runID: String,
        package: XcircuitePackage,
        projectRoot: URL
    ) throws -> URL {
        let runDirectory = try package.runDirectoryURL(for: runID)
        guard !artifactEnvelopeDirectoryExists(runDirectory) else {
            return runDirectory
        }
        return try ensureRunDirectory(for: runID, inProjectAt: projectRoot)
    }

    private func artifactEnvelopeDirectoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }
}

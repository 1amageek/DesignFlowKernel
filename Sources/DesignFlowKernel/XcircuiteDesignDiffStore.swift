import Foundation

extension XcircuitePackageStore {
    @discardableResult
    public func writeDesignDiff(
        _ diff: XcircuiteDesignDiff,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteFileReference {
        let package = XcircuitePackage(projectRoot: projectRoot)
        let runDirectory = try ensureRunDirectoryExists(
            runID: diff.runID,
            package: package,
            projectRoot: projectRoot
        )
        let diffURL = runDirectory.appending(path: "design-diff.json")
        try writeJSON(diff, to: diffURL, forProjectAt: projectRoot)

        let reference = try fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(diff.runID)/design-diff.json",
            kind: .designDiff,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: diff.runID
        )
        try upsertRunArtifact(reference, runID: diff.runID, inProjectAt: projectRoot)
        return reference
    }

    public func loadDesignDiff(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteDesignDiff {
        let package = XcircuitePackage(projectRoot: projectRoot)
        let diffURL = try package.runDirectoryURL(for: runID)
            .appending(path: "design-diff.json")
        return try readJSON(XcircuiteDesignDiff.self, from: diffURL)
    }

    public func upsertRunArtifact(
        _ reference: XcircuiteFileReference,
        runID: String,
        inProjectAt projectRoot: URL
    ) throws {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        if let artifactID = reference.artifactID {
            try XcircuiteIdentifierValidator().validate(artifactID, kind: .artifactID)
        }

        _ = try upsertRunArtifacts([reference], runID: runID, inProjectAt: projectRoot)
    }

    private func ensureRunDirectoryExists(
        runID: String,
        package: XcircuitePackage,
        projectRoot: URL
    ) throws -> URL {
        let runDirectory = try package.runDirectoryURL(for: runID)
        if directoryExists(runDirectory) {
            return runDirectory
        }
        return try ensureRunDirectory(for: runID, inProjectAt: projectRoot)
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }
}

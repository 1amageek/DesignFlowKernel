import Foundation

public struct XcircuiteWorkspaceStore: Sendable {
    private let hasher: XcircuiteHasher
    private let identifierValidator: XcircuiteIdentifierValidator
    let referenceVerifier: XcircuiteFileReferenceVerifier

    public init(
        hasher: XcircuiteHasher = XcircuiteHasher(),
        identifierValidator: XcircuiteIdentifierValidator = XcircuiteIdentifierValidator()
    ) {
        self.hasher = hasher
        self.identifierValidator = identifierValidator
        self.referenceVerifier = XcircuiteFileReferenceVerifier(hasher: hasher)
    }

    public func workspaceURL(forProjectAt projectRoot: URL) -> URL {
        XcircuiteWorkspace(projectRoot: projectRoot).workspaceURL
    }

    public func configurationURL(named fileName: String, inProjectAt projectRoot: URL) throws -> URL {
        try XcircuiteWorkspace(projectRoot: projectRoot).configurationURL(named: fileName)
    }

    public func createWorkspace(at projectRoot: URL) throws {
        try ensureWorkspaceDirectory(forProjectAt: projectRoot)
        let manifestURL = XcircuiteWorkspace(projectRoot: projectRoot).manifestURL
        let lockURL = workspaceURL(forProjectAt: projectRoot).appending(path: ".project.lock")
        try XcircuiteFileLock.withExclusiveLock(at: lockURL) {
            let path = manifestURL.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: path) {
                _ = try readJSON(XcircuiteProjectManifest.self, from: manifestURL)
                return
            }

            let displayName = projectRoot.lastPathComponent.isEmpty ? "Untitled" : projectRoot.lastPathComponent
            let manifest = XcircuiteProjectManifest.makeDefault(displayName: displayName)
            try saveManifest(manifest, forProjectAt: projectRoot)
        }
    }

    public func isWorkspace(at projectRoot: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = workspaceURL(forProjectAt: projectRoot).path(percentEncoded: false)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func ensureWorkspaceDirectory(forProjectAt projectRoot: URL) throws {
        try ensureDirectory(at: workspaceURL(forProjectAt: projectRoot))
    }

    public func ensureDirectory(at url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch {
            throw XcircuiteWorkspaceError.createDirectoryFailed(error.localizedDescription)
        }
    }

    public func url(forProjectRelativePath rawPath: String, inProjectAt projectRoot: URL) throws -> URL {
        try XcircuiteWorkspace(projectRoot: projectRoot).url(forProjectRelativePath: rawPath)
    }

    public func loadManifest(forProjectAt projectRoot: URL) throws -> XcircuiteProjectManifest {
        try readJSON(
            XcircuiteProjectManifest.self,
            named: XcircuiteWorkspace.manifestFileName,
            forProjectAt: projectRoot
        )
    }

    func saveManifest(
        _ manifest: XcircuiteProjectManifest,
        forProjectAt projectRoot: URL
    ) throws {
        try manifest.validate()
        try writeJSON(
            manifest,
            named: XcircuiteWorkspace.manifestFileName,
            forProjectAt: projectRoot
        )
    }

    public func fileReference(
        forProjectRelativePath path: String,
        artifactID: String? = nil,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        inProjectAt projectRoot: URL,
        producedByRunID: String? = nil,
        verifiedByRunID: String? = nil
    ) throws -> XcircuiteFileReference {
        if let artifactID {
            try identifierValidator.validate(artifactID, kind: .artifactID)
        }
        let fileURL = try url(forProjectRelativePath: path, inProjectAt: projectRoot)
        let digest = try hasher.sha256(fileAt: fileURL)
        let byteCount = try hasher.byteCount(fileAt: fileURL)
        return XcircuiteFileReference(
            artifactID: artifactID,
            path: path,
            kind: kind,
            format: format,
            sha256: digest,
            byteCount: byteCount,
            producedByRunID: producedByRunID,
            verifiedByRunID: verifiedByRunID
        )
    }

    public func upsertFileReference(
        _ reference: XcircuiteFileReference,
        forProjectAt projectRoot: URL
    ) throws {
        guard reference.artifactID != "run-manifest" else {
            throw XcircuiteWorkspaceError.runManifestCannotBeProjectFile(reference.path)
        }
        try updateProjectManifest(forProjectAt: projectRoot) { manifest in
            manifest.files.removeAll { $0.path == reference.path }
            manifest.files.append(reference)
            manifest.files.sort { $0.path < $1.path }
        }
    }

    public func writeText(_ text: String, to url: URL) throws {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw XcircuiteWorkspaceError.writeFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    public func writeJSON<T: Encodable>(
        _ value: T,
        named fileName: String,
        forProjectAt projectRoot: URL
    ) throws {
        let url = try configurationURL(named: fileName, inProjectAt: projectRoot)
        try writeJSON(value, to: url, forProjectAt: projectRoot)
    }

    public func writeJSON<T: Encodable>(
        _ value: T,
        to url: URL,
        forProjectAt projectRoot: URL
    ) throws {
        try ensureWorkspaceDirectory(forProjectAt: projectRoot)
        try validateProjectWriteURL(url, projectRoot: projectRoot)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw XcircuiteWorkspaceError.encodeFailed(error.localizedDescription)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw XcircuiteWorkspaceError.writeFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func validateProjectWriteURL(_ url: URL, projectRoot: URL) throws {
        let lexicalRoot = projectRoot.standardizedFileURL
        let lexicalDestination = url.standardizedFileURL
        guard lexicalDestination.isContained(in: lexicalRoot) else {
            throw XcircuiteWorkspaceError.unsafeProjectPath(url.path(percentEncoded: false))
        }

        let resolvedRoot = projectRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedAncestor = nearestExistingAncestor(for: url)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard resolvedAncestor.isContained(in: resolvedRoot) else {
            throw XcircuiteWorkspaceError.unsafeProjectPath(url.path(percentEncoded: false))
        }
    }

    private func nearestExistingAncestor(for url: URL) -> URL {
        var candidate = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate {
                return candidate
            }
            candidate = parent
        }
        return candidate
    }

    private func fileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }

    public func readJSON<T: Decodable>(
        _ type: T.Type,
        named fileName: String,
        forProjectAt projectRoot: URL
    ) throws -> T {
        let url = try configurationURL(named: fileName, inProjectAt: projectRoot)
        return try readJSON(type, from: url)
    }

    public func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XcircuiteWorkspaceError.readFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw XcircuiteWorkspaceError.decodeFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }
}

private extension URL {
    func isContained(in root: URL) -> Bool {
        let path = Self.privatePrefixNormalized(standardizedFileURL.path(percentEncoded: false))
        let rootPath = Self.privatePrefixNormalized(root.standardizedFileURL.path(percentEncoded: false))
        guard path != rootPath else {
            return true
        }

        let normalizedRootPath = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        return path.hasPrefix(normalizedRootPath)
    }

    /// `standardizedFileURL` strips a leading `/private` only when the
    /// path exists, so a containment check between an existing root and a
    /// not-yet-created destination under `/private/tmp` (or `/private/var`)
    /// compares asymmetric spellings of the same location. Strip the
    /// prefix on both sides so the comparison stays purely lexical.
    static func privatePrefixNormalized(_ path: String) -> String {
        for alias in ["/private/tmp", "/private/var", "/private/etc"] {
            if path == alias || path.hasPrefix("\(alias)/") {
                return String(path.dropFirst("/private".count))
            }
        }
        return path
    }
}

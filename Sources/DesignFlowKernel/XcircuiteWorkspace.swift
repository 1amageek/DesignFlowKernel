import Foundation

public struct XcircuiteWorkspace: Sendable, Hashable {
    public static let directoryName = ".xcircuite"
    public static let manifestFileName = "project.json"

    public let projectRoot: URL

    public init(projectRoot: URL) {
        self.projectRoot = projectRoot
    }

    public var workspaceURL: URL {
        projectRoot.appending(path: Self.directoryName)
    }

    public var manifestURL: URL {
        workspaceURL.appending(path: Self.manifestFileName)
    }

    public func configurationURL(named fileName: String) throws -> URL {
        try validateWorkspaceFileName(fileName)
        return workspaceURL.appending(path: fileName)
    }

    public func runDirectoryURL(for runID: String) throws -> URL {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        return workspaceURL
            .appending(path: "runs")
            .appending(path: runID)
    }

    public func url(forProjectRelativePath rawPath: String) throws -> URL {
        try Self.validateProjectRelativePath(rawPath)

        let root = projectRoot.standardizedFileURL
        let resolved = root.appending(path: rawPath).standardizedFileURL

        guard resolved.isContained(in: root),
              resolved.isContainedAfterResolvingExistingPathComponents(in: root) else {
            throw XcircuiteWorkspaceError.unsafeProjectPath(rawPath)
        }

        return resolved
    }

    static func validateProjectRelativePath(_ rawPath: String) throws {
        guard !rawPath.isEmpty, rawPath != "." else {
            throw XcircuiteWorkspaceError.unsafeProjectPath(rawPath)
        }

        if rawPath.hasPrefix("/") || rawPath.hasPrefix("~") {
            throw XcircuiteWorkspaceError.unsafeProjectPath(rawPath)
        }

        let components = rawPath.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
            throw XcircuiteWorkspaceError.unsafeProjectPath(rawPath)
        }
    }

    private func validateWorkspaceFileName(_ fileName: String) throws {
        guard !fileName.isEmpty, fileName != ".", fileName != ".." else {
            throw XcircuiteWorkspaceError.unsafeProjectPath(fileName)
        }
        if fileName.hasPrefix("/") || fileName.hasPrefix("~") || fileName.contains("/") {
            throw XcircuiteWorkspaceError.unsafeProjectPath(fileName)
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

    func isContainedAfterResolvingExistingPathComponents(in root: URL) -> Bool {
        guard isContained(in: root) else {
            return false
        }

        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        let path = standardizedFileURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        guard path != rootPath else {
            return true
        }
        guard path.hasPrefix(rootPrefix) else {
            return false
        }

        let rootResolvedURL = rootURL.resolvingSymlinksInPath()
        let relativePath = String(path.dropFirst(rootPrefix.count))
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        var probe = rootURL
        let fileManager = FileManager.default

        for component in components {
            probe = probe.appending(path: String(component))
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: probe.path(percentEncoded: false), isDirectory: &isDirectory) else {
                return true
            }

            let resolvedProbe = probe.standardizedFileURL.resolvingSymlinksInPath()
            guard resolvedProbe.isContained(in: rootResolvedURL) else {
                return false
            }
        }

        return true
    }
}

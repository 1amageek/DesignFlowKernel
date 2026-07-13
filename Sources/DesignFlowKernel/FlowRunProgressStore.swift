import Foundation

public struct FlowRunProgressStore: Sendable {
    public static let progressRelativePath = "progress.jsonl"
    public static let cancellationRelativePath = "cancellation.json"

    private let packageStore: any FlowExecutionStorage

    public init(
        packageStore: any FlowExecutionStorage = DesignFlowStorageDefaults.makeExecutionStorage()
    ) {
        self.packageStore = packageStore
    }

    @discardableResult
    public func appendEvent(
        runID: String,
        projectRoot: URL,
        kind: FlowRunProgressEventKind,
        stageID: String? = nil,
        stageStatus: FlowStageStatus? = nil,
        runStatus: FlowRunStatus? = nil,
        message: String
    ) throws -> FlowRunProgressEvent {
        let sequence = try nextProgressSequence(runID: runID, projectRoot: projectRoot)
        let event = FlowRunProgressEvent(
            runID: runID,
            sequence: sequence,
            kind: kind,
            stageID: stageID,
            stageStatus: stageStatus,
            runStatus: runStatus,
            message: message
        )
        try appendJSONLine(event, to: progressURL(runID: runID, projectRoot: projectRoot), projectRoot: projectRoot)
        try upsertRunLevelArtifactIfManifestExists(
            runID: runID,
            projectRoot: projectRoot,
            relativePath: Self.progressRelativePath,
            artifactID: "run-progress",
            format: .text
        )
        return event
    }

    private func nextProgressSequence(
        runID: String,
        projectRoot: URL
    ) throws -> Int {
        let url = progressURL(runID: runID, projectRoot: projectRoot)
        guard fileExists(url) else {
            return 1
        }
        guard let line = try lastNonEmptyJSONLine(from: url) else {
            return 1
        }
        let decoder = JSONDecoder()
        do {
            let latest = try decoder.decode(FlowRunProgressEvent.self, from: line)
            return latest.sequence + 1
        } catch {
            throw XcircuitePackageError.decodeFailed(
                "\(Self.progressRelativePath): latest progress line is invalid: \(error.localizedDescription)"
            )
        }
    }

    public func loadProgressEvents(
        runID: String,
        projectRoot: URL
    ) throws -> [FlowRunProgressEvent] {
        let url = progressURL(runID: runID, projectRoot: projectRoot)
        guard fileExists(url) else {
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XcircuitePackageError.readFailed(
                "\(Self.progressRelativePath): \(error.localizedDescription)"
            )
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw XcircuitePackageError.decodeFailed("\(Self.progressRelativePath): invalid UTF-8")
        }
        let decoder = JSONDecoder()
        return try text
            .split(separator: "\n")
            .map { line in
                guard let lineData = String(line).data(using: .utf8) else {
                    throw XcircuitePackageError.decodeFailed("\(Self.progressRelativePath): invalid UTF-8 line")
                }
                return try decoder.decode(FlowRunProgressEvent.self, from: lineData)
            }
    }

    public func persistCancellationRequest(
        _ request: FlowRunCancellationRequest,
        projectRoot: URL
    ) throws -> FlowRunCancellationResult {
        let url = cancellationURL(runID: request.runID, projectRoot: projectRoot)
        try ensureRunDirectory(runID: request.runID, projectRoot: projectRoot)
        try packageStore.writeJSON(request, to: url, forProjectAt: projectRoot)
        try upsertRunLevelArtifactIfManifestExists(
            runID: request.runID,
            projectRoot: projectRoot,
            relativePath: Self.cancellationRelativePath,
            artifactID: "run-cancellation-request",
            format: .json
        )
        return FlowRunCancellationResult(
            status: "recorded",
            request: request,
            path: "\(XcircuitePackage.directoryName)/runs/\(request.runID)/\(Self.cancellationRelativePath)"
        )
    }

    public func loadCancellationRequest(
        runID: String,
        projectRoot: URL
    ) throws -> FlowRunCancellationRequest? {
        let url = cancellationURL(runID: runID, projectRoot: projectRoot)
        guard fileExists(url) else {
            return nil
        }
        return try packageStore.readJSON(FlowRunCancellationRequest.self, from: url)
    }

    public func runLevelArtifacts(
        runID: String,
        projectRoot: URL
    ) throws -> [XcircuiteFileReference] {
        var artifacts: [XcircuiteFileReference] = []
        if fileExists(progressURL(runID: runID, projectRoot: projectRoot)) {
            artifacts.append(try packageStore.fileReference(
                forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.progressRelativePath)",
                artifactID: "run-progress",
                kind: .other,
                format: .text,
                inProjectAt: projectRoot,
                producedByRunID: runID
            ))
        }
        if fileExists(cancellationURL(runID: runID, projectRoot: projectRoot)) {
            artifacts.append(try packageStore.fileReference(
                forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.cancellationRelativePath)",
                artifactID: "run-cancellation-request",
                kind: .other,
                format: .json,
                inProjectAt: projectRoot,
                producedByRunID: runID
            ))
        }
        return artifacts
    }

    private func appendJSONLine<T: Encodable>(
        _ value: T,
        to url: URL,
        projectRoot: URL
    ) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw XcircuitePackageError.encodeFailed(error.localizedDescription)
        }
        var line = data
        line.append(0x0A)
        do {
            if fileExists(url) {
                let handle = try FileHandle(forWritingTo: url)
                defer { handle.closeFile() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url, options: .atomic)
            }
        } catch {
            throw XcircuitePackageError.writeFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func lastNonEmptyJSONLine(from url: URL) throws -> Data? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw XcircuitePackageError.readFailed(
                "\(Self.progressRelativePath): \(error.localizedDescription)"
            )
        }
        defer { handle.closeFile() }

        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
        } catch {
            throw XcircuitePackageError.readFailed(
                "\(Self.progressRelativePath): \(error.localizedDescription)"
            )
        }
        guard fileSize > 0 else {
            return nil
        }

        let chunkSize: UInt64 = 64 * 1_024
        var offset = fileSize
        var buffer = Data()
        while offset > 0 {
            let readSize = min(chunkSize, offset)
            offset -= readSize
            do {
                try handle.seek(toOffset: offset)
                let chunk = try handle.read(upToCount: Int(readSize)) ?? Data()
                var combined = Data()
                combined.append(chunk)
                combined.append(buffer)
                buffer = combined
            } catch {
                throw XcircuitePackageError.readFailed(
                    "\(Self.progressRelativePath): \(error.localizedDescription)"
                )
            }

            let lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: true)
            if let latest = lines.last, offset == 0 || lines.count > 1 {
                return Data(latest)
            }
        }

        return nil
    }

    private func ensureRunDirectory(runID: String, projectRoot: URL) throws {
        try packageStore.ensurePackageDirectory(forProjectAt: projectRoot)
        try ensureDirectory(XcircuitePackage(projectRoot: projectRoot).packageURL.appending(path: "runs"))
        try ensureDirectory(runDirectoryURL(runID: runID, projectRoot: projectRoot))
    }

    private func upsertRunLevelArtifactIfManifestExists(
        runID: String,
        projectRoot: URL,
        relativePath: String,
        artifactID: String,
        format: XcircuiteFileFormat
    ) throws {
        guard fileExists(runDirectoryURL(runID: runID, projectRoot: projectRoot).appending(path: "manifest.json")) else {
            return
        }
        let reference = try packageStore.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(relativePath)",
            artifactID: artifactID,
            kind: .other,
            format: format,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
    }

    private func ensureDirectory(_ url: URL) throws {
        try packageStore.ensureDirectory(at: url)
    }

    private func progressURL(runID: String, projectRoot: URL) -> URL {
        runDirectoryURL(runID: runID, projectRoot: projectRoot)
            .appending(path: Self.progressRelativePath)
    }

    private func cancellationURL(runID: String, projectRoot: URL) -> URL {
        runDirectoryURL(runID: runID, projectRoot: projectRoot)
            .appending(path: Self.cancellationRelativePath)
    }

    private func runDirectoryURL(runID: String, projectRoot: URL) -> URL {
        XcircuitePackage(projectRoot: projectRoot)
            .packageURL
            .appending(path: "runs")
            .appending(path: runID)
    }

    private func fileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }
}

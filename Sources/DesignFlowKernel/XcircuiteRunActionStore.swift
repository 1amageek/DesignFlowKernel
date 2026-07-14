import Foundation

extension XcircuiteWorkspaceStore {
    public func appendRunAction(
        _ record: XcircuiteRunActionRecord,
        inProjectAt projectRoot: URL
    ) throws {
        let package = XcircuiteWorkspace(projectRoot: projectRoot)
        let runDirectory = try package.runDirectoryURL(for: record.runID)
        guard runActionDirectoryExists(runDirectory) else {
            throw XcircuiteWorkspaceError.readFailed("run directory does not exist: \(record.runID)")
        }
        try appendJSONLine(record, to: runDirectory.appending(path: "actions.jsonl"))
        let reference = try fileReference(
            forProjectRelativePath: "\(XcircuiteWorkspace.directoryName)/runs/\(record.runID)/actions.jsonl",
            artifactID: "run-action-ledger",
            kind: .other,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: record.runID
        )
        try upsertRunArtifact(reference, runID: record.runID, inProjectAt: projectRoot)
    }

    public func loadRunActions(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> [XcircuiteRunActionRecord] {
        let package = XcircuiteWorkspace(projectRoot: projectRoot)
        let actionsURL = try package.runDirectoryURL(for: runID)
            .appending(path: "actions.jsonl")
        guard runActionFileExists(actionsURL) else {
            return []
        }

        let text: String
        do {
            text = try String(contentsOf: actionsURL, encoding: .utf8)
        } catch {
            throw XcircuiteWorkspaceError.readFailed(
                "\(actionsURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        let decoder = JSONDecoder()
        var records: [XcircuiteRunActionRecord] = []
        for line in text.split(separator: "\n") {
            let data = Data(line.utf8)
            do {
                records.append(try decoder.decode(XcircuiteRunActionRecord.self, from: data))
            } catch {
                throw XcircuiteWorkspaceError.decodeFailed(
                    "\(actionsURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
        return records
    }

    public func loadSuggestedCommandSelections(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> [XcircuiteSuggestedCommandSelection] {
        var selections: [XcircuiteSuggestedCommandSelection] = []
        for record in try loadRunActions(runID: runID, inProjectAt: projectRoot) {
            if let selection = try XcircuiteSuggestedCommandSelection(record: record) {
                selections.append(selection)
            }
        }
        return selections
    }

    public func loadLatestSuggestedCommandSelection(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteSuggestedCommandSelection? {
        try loadSuggestedCommandSelections(runID: runID, inProjectAt: projectRoot).last
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw XcircuiteWorkspaceError.encodeFailed(error.localizedDescription)
        }

        var line = data
        line.append(0x0A)

        if runActionFileExists(url) {
            do {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } catch {
                throw XcircuiteWorkspaceError.writeFailed(
                    "\(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        } else {
            do {
                try line.write(to: url, options: .atomic)
            } catch {
                throw XcircuiteWorkspaceError.writeFailed(
                    "\(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
    }

    private func runActionDirectoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    private func runActionFileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }
}

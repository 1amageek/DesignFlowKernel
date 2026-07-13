import Foundation

extension XcircuitePackageStore {
    @discardableResult
    public func writeLoopIterationSummaries(
        _ summaries: [XcircuiteLoopIterationSummary],
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteFileReference {
        let relativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/loop/iterations.jsonl"
        let url = projectRoot.appending(path: relativePath)
        try ensureDirectory(at: url.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try summaries.map { summary in
            let data = try encoder.encode(summary)
            guard let text = String(data: data, encoding: .utf8) else {
                throw XcircuitePackageError.encodeFailed("loop iteration summary was not UTF-8")
            }
            return text
        }
        try writeText(lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"), to: url)
        let reference = try fileReference(
            forProjectRelativePath: relativePath,
            artifactID: "agent-loop-iterations",
            kind: .report,
            format: .text,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func writeAgentLoopSnapshot(
        _ snapshot: XcircuiteAgentLoopSnapshot,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteFileReference {
        let relativePath = "\(XcircuitePackage.directoryName)/runs/\(snapshot.runID)/loop/snapshot.json"
        let url = projectRoot.appending(path: relativePath)
        try ensureDirectory(at: url.deletingLastPathComponent())
        try writeJSON(snapshot, to: url, forProjectAt: projectRoot)
        let reference = try fileReference(
            forProjectRelativePath: relativePath,
            artifactID: "agent-loop-snapshot",
            kind: .report,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: snapshot.runID
        )
        try upsertRunArtifact(reference, runID: snapshot.runID, inProjectAt: projectRoot)
        return reference
    }

    @discardableResult
    public func writeRunGuardVerdict(
        _ verdict: XcircuiteRunGuardVerdict,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteFileReference {
        let relativePath = "\(XcircuitePackage.directoryName)/runs/\(verdict.runID)/loop/guard-verdict.json"
        let url = projectRoot.appending(path: relativePath)
        try ensureDirectory(at: url.deletingLastPathComponent())
        try writeJSON(verdict, to: url, forProjectAt: projectRoot)
        let reference = try fileReference(
            forProjectRelativePath: relativePath,
            artifactID: "run-guard-verdict",
            kind: .report,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: verdict.runID
        )
        try upsertRunArtifact(reference, runID: verdict.runID, inProjectAt: projectRoot)
        return reference
    }
}


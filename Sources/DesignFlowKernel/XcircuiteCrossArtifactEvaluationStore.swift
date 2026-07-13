import Foundation

extension XcircuitePackageStore {
    @discardableResult
    public func writeCrossArtifactEvaluation(
        _ evaluation: XcircuiteCrossArtifactEvaluation,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteFileReference {
        let relativePath = "\(XcircuitePackage.directoryName)/runs/\(evaluation.runID)/reports/cross-artifact-evaluation.json"
        let url = projectRoot.appending(path: relativePath)
        try ensureDirectory(at: url.deletingLastPathComponent())
        try writeJSON(evaluation, to: url, forProjectAt: projectRoot)
        let reference = try fileReference(
            forProjectRelativePath: relativePath,
            artifactID: "cross-artifact-evaluation",
            kind: .report,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: evaluation.runID
        )
        try upsertRunArtifact(reference, runID: evaluation.runID, inProjectAt: projectRoot)
        return reference
    }
}

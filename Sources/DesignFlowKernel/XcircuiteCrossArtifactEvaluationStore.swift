import CircuiteFoundation
import Foundation

extension FlowExecutionStorage {
    @discardableResult
    public func writeCrossArtifactEvaluation(
        _ evaluation: XcircuiteCrossArtifactEvaluation,
        inProjectAt projectRoot: URL
    ) throws -> ArtifactReference {
        let relativePath = ".xcircuite/runs/\(evaluation.runID)/reports/cross-artifact-evaluation.json"
        let url = try url(forProjectRelativePath: relativePath, inProjectAt: projectRoot)
        try ensureDirectory(at: url.deletingLastPathComponent())
        try writeJSON(evaluation, to: url, forProjectAt: projectRoot)
        let reference = try makeArtifactReference(
            forProjectRelativePath: relativePath,
            artifactID: "cross-artifact-evaluation",
            role: .output,
            kind: .report,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: evaluation.runID,
            verifiedByRunID: nil
        )
        try registerArtifact(
            reference,
            runID: evaluation.runID,
            inProjectAt: projectRoot
        )
        return reference
    }
}

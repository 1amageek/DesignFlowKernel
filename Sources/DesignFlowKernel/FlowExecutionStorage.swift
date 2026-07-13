import CircuiteFoundation
import Foundation

/// Storage capabilities required by a flow stage while it is executing.
///
/// The flow kernel depends on this capability set rather than on a concrete
/// workspace implementation. A host may provide a filesystem-backed store,
/// an in-memory fixture, or a remote workspace implementation without
/// changing stage executors.
public protocol FlowExecutionStorage: Sendable {
    func ensurePackageDirectory(forProjectAt projectRoot: URL) throws

    @discardableResult
    func ensureRunDirectory(
        for runID: String,
        inProjectAt projectRoot: URL
    ) throws -> URL

    func runDirectory(
        for runID: String,
        inProjectAt projectRoot: URL
    ) throws -> URL

    func ensureDirectory(at url: URL) throws

    func url(
        forProjectRelativePath path: String,
        inProjectAt projectRoot: URL
    ) throws -> URL

    func writeText(_ text: String, to url: URL) throws

    func writeJSON<T: Encodable>(
        _ value: T,
        to url: URL,
        forProjectAt projectRoot: URL
    ) throws

    func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T

    func fileReference(
        forProjectRelativePath path: String,
        artifactID: String?,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        inProjectAt projectRoot: URL,
        producedByRunID: String?,
        verifiedByRunID: String?
    ) throws -> XcircuiteFileReference

    func upsertRunArtifact(
        _ reference: XcircuiteFileReference,
        runID: String,
        inProjectAt projectRoot: URL
    ) throws

    func writeArtifactEnvelope(
        _ envelope: XcircuiteArtifactEnvelope,
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> ArtifactReference

    func loadApproval(
        runID: String,
        stageID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteApprovalRecord?

    func loadApprovals(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> [XcircuiteApprovalRecord]

    func loadCancellationRequest(
        runID: String,
        projectRoot: URL
    ) throws -> FlowRunCancellationRequest?
}

public extension FlowExecutionStorage {
    /// Convenience overload preserving the store API's optional provenance
    /// arguments while callers migrate to the protocol.
    func fileReference(
        forProjectRelativePath path: String,
        artifactID: String? = nil,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        inProjectAt projectRoot: URL,
        producedByRunID: String? = nil,
        verifiedByRunID: String? = nil
    ) throws -> XcircuiteFileReference {
        try fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: kind,
            format: format,
            inProjectAt: projectRoot,
            producedByRunID: producedByRunID,
            verifiedByRunID: verifiedByRunID
        )
    }
}

extension XcircuitePackageStore: FlowExecutionStorage {
    public func runDirectory(
        for runID: String,
        inProjectAt projectRoot: URL
    ) throws -> URL {
        try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
    }

    public func loadCancellationRequest(
        runID: String,
        projectRoot: URL
    ) throws -> FlowRunCancellationRequest? {
        try FlowRunProgressStore(packageStore: self).loadCancellationRequest(
            runID: runID,
            projectRoot: projectRoot
        )
    }
}

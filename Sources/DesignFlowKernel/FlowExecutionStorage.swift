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

    func loadRunManifest(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteRunManifest

    func loadRunActions(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> [XcircuiteRunActionRecord]

    func loadSuggestedCommandSelections(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> [XcircuiteSuggestedCommandSelection]

    func loadApprovals(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> [XcircuiteApprovalRecord]

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

    /// Creates the canonical Foundation artifact reference for a project file.
    ///
    /// Implementations may use a legacy persistence format internally, but the
    /// execution boundary never exposes that representation to new callers.
    func makeArtifactReference(
        forProjectRelativePath path: String,
        artifactID: String?,
        role: ArtifactRole,
        kind: ArtifactKind,
        format: ArtifactFormat,
        inProjectAt projectRoot: URL,
        producedByRunID: String?,
        verifiedByRunID: String?
    ) throws -> ArtifactReference

    /// Registers a canonical artifact in the run ledger.
    func registerArtifact(
        _ reference: ArtifactReference,
        runID: String,
        inProjectAt projectRoot: URL
    ) throws

    @available(*, deprecated, message: "Use makeArtifactReference(forProjectRelativePath:artifactID:role:kind:format:inProjectAt:producedByRunID:verifiedByRunID:).")
    func fileReference(
        forProjectRelativePath path: String,
        artifactID: String?,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        inProjectAt projectRoot: URL,
        producedByRunID: String?,
        verifiedByRunID: String?
    ) throws -> XcircuiteFileReference

    @available(*, deprecated, message: "Use registerArtifact(_:runID:inProjectAt:).")
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
    public func makeArtifactReference(
        forProjectRelativePath path: String,
        artifactID: String?,
        role: ArtifactRole = .legacyUnspecified,
        kind: ArtifactKind,
        format: ArtifactFormat,
        inProjectAt projectRoot: URL,
        producedByRunID: String? = nil,
        verifiedByRunID: String? = nil
    ) throws -> ArtifactReference {
        let legacyReference = try fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: XcircuiteFileKind(foundationRawValue: kind.rawValue),
            format: XcircuiteFileFormat(foundationRawValue: format.rawValue),
            inProjectAt: projectRoot,
            producedByRunID: producedByRunID,
            verifiedByRunID: verifiedByRunID
        )
        let foundationReference = try legacyReference.foundationArtifactReference()
        guard role != .legacyUnspecified else {
            return foundationReference
        }
        return ArtifactReference(
            id: foundationReference.id,
            locator: ArtifactLocator(
                location: foundationReference.locator.location,
                role: role,
                kind: foundationReference.locator.kind,
                format: foundationReference.locator.format
            ),
            digest: foundationReference.digest,
            byteCount: foundationReference.byteCount,
            producer: foundationReference.producer
        )
    }

    public func registerArtifact(
        _ reference: ArtifactReference,
        runID: String,
        inProjectAt projectRoot: URL
    ) throws {
        try upsertRunArtifact(
            reference.legacyXcircuiteReference(),
            runID: runID,
            inProjectAt: projectRoot
        )
    }

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

private extension XcircuiteFileKind {
    init(foundationRawValue rawValue: String) {
        switch rawValue {
        case "power-intent": self = .powerIntent
        case "timing-library": self = .timingLibrary
        case "test-pattern": self = .testPattern
        case "rule-deck": self = .ruleDeck
        case "design-diff": self = .designDiff
        case "parasitics": self = .parasitic
        default: self = XcircuiteFileKind(rawValue: rawValue) ?? .other
        }
    }
}

private extension XcircuiteFileFormat {
    init(foundationRawValue rawValue: String) {
        switch rawValue {
        case "system-verilog": self = .systemVerilog
        default: self = XcircuiteFileFormat(rawValue: rawValue.uppercased()) ?? .unknown
        }
    }
}

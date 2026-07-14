import Foundation

public protocol XcircuiteRunLedgerStoring: Sendable {
    func createWorkspace(at projectRoot: URL) throws

    @discardableResult
    func createRunDirectory(
        for runID: String,
        descriptor: XcircuiteRunDescriptor,
        inProjectAt projectRoot: URL
    ) throws -> URL

    @discardableResult
    func ensureRunDirectory(
        for runID: String,
        descriptor: XcircuiteRunDescriptor,
        inProjectAt projectRoot: URL
    ) throws -> URL

    func loadRunManifest(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteRunManifest

    func listRunSnapshots(
        inProjectAt projectRoot: URL
    ) throws -> [XcircuiteRunSnapshot]

    @discardableResult
    func transitionRun(
        runID: String,
        transition: XcircuiteRunTransition,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteRunManifest

    @discardableResult
    func upsertRunArtifacts(
        _ references: [XcircuiteFileReference],
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteRunManifest
}

extension XcircuiteWorkspaceStore: XcircuiteRunLedgerStoring {}

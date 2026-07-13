import Foundation

/// Serializes typed run-ledger updates behind the kernel persistence protocol.
///
/// The coordinator owns lifecycle ordering only. Storage format, filesystem
/// boundaries, and recovery details remain in the injected implementation.
public actor FlowRunLedgerCoordinator {
    private let persistence: any FlowRunLedgerPersisting

    public init(persistence: any FlowRunLedgerPersisting) {
        self.persistence = persistence
    }

    public func load(
        runID: String,
        projectRoot: URL
    ) async throws -> FlowRunLedger {
        try await persistence.loadRunLedger(runID: runID, projectRoot: projectRoot)
    }

    public func save(
        _ ledger: FlowRunLedger,
        projectRoot: URL
    ) async throws {
        try await persistence.saveRunLedger(ledger, projectRoot: projectRoot)
    }

    @discardableResult
    public func update(
        runID: String,
        projectRoot: URL,
        _ mutation: @Sendable (inout FlowRunLedger) throws -> Void
    ) async throws -> FlowRunLedger {
        var ledger = try await load(runID: runID, projectRoot: projectRoot)
        guard ledger.runID == runID else {
            throw FlowRunLedgerPersistenceError.runIdentifierMismatch(
                requested: runID,
                stored: ledger.runID
            )
        }
        try mutation(&ledger)
        try await save(ledger, projectRoot: projectRoot)
        return ledger
    }
}

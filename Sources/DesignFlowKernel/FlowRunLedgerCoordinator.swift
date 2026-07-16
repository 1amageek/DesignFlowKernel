import CircuiteFoundation
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
        runID: String
    ) async throws -> FlowRunLedger {
        try await persistence.loadRunLedger(runID: runID)
    }

    public func save(
        _ ledger: FlowRunLedger
    ) async throws {
        try await persistence.saveRunLedger(ledger)
    }

    @discardableResult
    public func update(
        runID: String,
        _ mutation: @Sendable (inout FlowRunLedger) throws -> Void
    ) async throws -> FlowRunLedger {
        var ledger = try await load(runID: runID)
        guard ledger.runID == runID else {
            throw FlowRunLedgerPersistenceError.runIdentifierMismatch(
                requested: runID,
                stored: ledger.runID
            )
        }
        let originalRevision = ledger.runManifest.revision
        let originalUpdatedAt = ledger.runManifest.updatedAt
        try mutation(&ledger)
        guard ledger.runManifest.revision == originalRevision else {
            throw FlowRunLedgerPersistenceError.storageFailed(
                "Ledger mutations must not modify revision directly."
            )
        }
        ledger.runManifest.revision = originalRevision + 1
        ledger.runManifest.updatedAt = max(Date(), originalUpdatedAt)
        try await save(ledger)
        return try await load(runID: runID)
    }

    @discardableResult
    public func transition(
        runID: String,
        to status: FlowRunStatus,
        registering artifacts: [ArtifactReference] = [],
        at timestamp: Date = Date()
    ) async throws -> FlowRunLedger {
        try await update(runID: runID) { ledger in
            let current = ledger.runManifest.status
            let next = Self.manifestStatus(status)
            guard current.canTransition(to: next) else {
                throw FlowRunLedgerPersistenceError.invalidTransition(
                    runID: runID,
                    from: current.rawValue,
                    to: next.rawValue
                )
            }
            ledger.runManifest.status = next
            for reference in artifacts {
                ledger.artifacts.removeAll {
                    $0.locator.location == reference.locator.location
                        || $0.id == reference.id
                }
                ledger.artifacts.append(reference)
            }
            ledger.artifacts.sort {
                $0.locator.location.value < $1.locator.location.value
            }
            switch next {
            case .created:
                break
            case .running:
                ledger.runManifest.startedAt = ledger.runManifest.startedAt ?? timestamp
                ledger.runManifest.finishedAt = nil
            case .succeeded, .failed, .cancelled, .blocked, .partial:
                ledger.runManifest.startedAt = ledger.runManifest.startedAt ?? timestamp
                ledger.runManifest.finishedAt = timestamp
            }
        }
    }

    /// Registers canonical artifacts without changing the run lifecycle state.
    ///
    /// Ledger and manifest projections are updated atomically so persistence
    /// implementations never need access to kernel-owned manifest setters.
    @discardableResult
    public func register(
        runID: String,
        artifacts: [ArtifactReference]
    ) async throws -> FlowRunLedger {
        try await update(runID: runID) { ledger in
            for reference in artifacts {
                ledger.artifacts.removeAll {
                    $0.locator.location == reference.locator.location
                        || $0.id == reference.id
                }
                ledger.artifacts.append(reference)
            }
            ledger.artifacts.sort {
                $0.locator.location.value < $1.locator.location.value
            }
            ledger.runManifest.artifacts = ledger.artifacts
        }
    }

    private static func manifestStatus(_ status: FlowRunStatus) -> FlowRunStatus {
        switch status {
        case .created: .created
        case .running: .running
        case .succeeded: .succeeded
        case .failed: .failed
        case .blocked: .blocked
        case .cancelled: .cancelled
        case .partial: .partial
        }
    }
}

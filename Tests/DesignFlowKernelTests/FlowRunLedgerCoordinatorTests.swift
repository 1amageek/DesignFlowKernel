import CircuiteFoundation
import Foundation
import Testing
@testable import DesignFlowKernel

@Suite("FlowRunLedgerCoordinator")
struct FlowRunLedgerCoordinatorTests {
    @Test
    func serializesLoadUpdateAndSaveThroughPersistenceProtocol() async throws {
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: "run-1"))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)

        let updated = try await coordinator.update(
            runID: "run-1"
        ) { ledger in
            ledger.progressEvents.append(
                FlowRunProgressEvent(
                    runID: "run-1",
                    sequence: 1,
                    kind: .runStarted,
                    runStatus: .running,
                    message: "started"
                )
            )
        }

        #expect(updated.progressEvents.count == 1)
        let persisted = try await coordinator.load(runID: "run-1")
        #expect(persisted == updated)
        #expect(await store.saveCount == 1)
    }

    @Test
    func rejectsRunIdentifierMismatchBeforeSaving() async throws {
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: "run-1"))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)

        await #expect(throws: FlowRunLedgerPersistenceError.runIdentifierMismatch(
            requested: "run-2",
            stored: "run-1"
        )) {
            try await coordinator.update(runID: "run-2") { _ in }
        }
        #expect(await store.saveCount == 0)
    }

    @Test
    func persistsCompleteLifecycleTransitions() async throws {
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: "run-lifecycle"))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)

        let running = try await coordinator.transition(
            runID: "run-lifecycle",
            to: .running,
            at: Date(timeIntervalSince1970: 1_700_000_010)
        )
        #expect(running.runManifest.status == .running)
        #expect(running.runManifest.startedAt != nil)
        #expect(running.runManifest.finishedAt == nil)

        let succeeded = try await coordinator.transition(
            runID: "run-lifecycle",
            to: .succeeded,
            at: Date(timeIntervalSince1970: 1_700_000_020)
        )
        #expect(succeeded.runManifest.status == .succeeded)
        #expect(succeeded.runManifest.finishedAt == Date(timeIntervalSince1970: 1_700_000_020))
        #expect(succeeded.runManifest.revision == 2)
    }

    @Test
    func rejectsInvalidTerminalTransition() async throws {
        var ledger = try makeLedger(runID: "run-final")
        ledger.runManifest.status = .succeeded
        let store = InMemoryLedgerStore(ledger: ledger)
        let coordinator = FlowRunLedgerCoordinator(persistence: store)

        await #expect(throws: FlowRunLedgerPersistenceError.invalidTransition(
            runID: "run-final",
            from: FlowRunStatus.succeeded.rawValue,
            to: FlowRunStatus.running.rawValue
        )) {
            try await coordinator.transition(
                runID: "run-final",
                to: .running
            )
        }
        #expect(await store.saveCount == 0)
    }

    @Test
    func recordsApprovalAndResumeStateWithoutStorageKnowledge() async throws {
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: "run-review"))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        let plan = try artifactReference(id: "plan", path: ".xcircuite/runs/run-review/plan.json")
        let stageResult = try artifactReference(
            id: "stage-result",
            path: ".xcircuite/runs/run-review/stages/layout/result.json"
        )
        let approval = FlowApprovalRecord(
            runID: "run-review",
            stageID: "layout",
            verdict: .approved,
            reviewer: "reviewer",
            reviewerKind: .human,
            note: "reviewed",
            createdAt: Date(timeIntervalSince1970: 1_700_000_030),
            evidence: FlowApprovalEvidenceBinding(plan: plan, stageResult: stageResult)
        )

        let updated = try await coordinator.update(runID: "run-review") {
            $0.approvals.append(approval)
            $0.runManifest.status = .blocked
        }
        #expect(updated.approvals == [approval])
        #expect(updated.runManifest.status == .blocked)

        let resumed = try await coordinator.transition(
            runID: "run-review",
            to: .running
        )
        #expect(resumed.runManifest.status == .running)
        #expect(resumed.approvals == [approval])
    }

    @Test
    func recordsCancellationAsTerminalLifecycleState() async throws {
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: "run-cancel"))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        _ = try await coordinator.transition(runID: "run-cancel", to: .running)
        let request = try FlowRunCancellationRequest(
            runID: "run-cancel",
            requestedBy: "operator",
            reason: "stop requested",
            requestedAt: Date(timeIntervalSince1970: 1_700_000_040)
        )
        _ = try await coordinator.update(runID: "run-cancel") {
            $0.cancellationRequest = request
        }
        let cancelled = try await coordinator.transition(
            runID: "run-cancel",
            to: .cancelled
        )
        #expect(cancelled.runManifest.status == .cancelled)
        #expect(cancelled.cancellationRequest == request)
        #expect(cancelled.runManifest.finishedAt != nil)
    }

    @Test
    func rejectsMutationThatBypassesRevisionOwnership() async throws {
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: "run-revision"))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)

        await #expect(throws: FlowRunLedgerPersistenceError.storageFailed(
            "Ledger mutations must not modify revision directly."
        )) {
            try await coordinator.update(runID: "run-revision") {
                $0.runManifest.revision += 1
            }
        }
        #expect(await store.saveCount == 0)
    }

    @Test
    func rejectsOneOfTwoConcurrentStaleUpdates() async throws {
        let store = CoordinatedCASLedgerStore(ledger: try makeLedger(runID: "run-concurrent"))
        let first = FlowRunLedgerCoordinator(persistence: store)
        let second = FlowRunLedgerCoordinator(persistence: store)

        async let firstUpdate = capture {
            try await first.update(runID: "run-concurrent") {
                $0.progressEvents.append(Self.progressEvent(sequence: 1))
            }
        }
        async let secondUpdate = capture {
            try await second.update(runID: "run-concurrent") {
                $0.progressEvents.append(Self.progressEvent(sequence: 2))
            }
        }

        var successes = 0
        var conflicts = 0
        for result in await [firstUpdate, secondUpdate] {
            switch result {
            case .success:
                successes += 1
            case .failure(let error):
                if let persistenceError = error as? FlowRunLedgerPersistenceError,
                   case .concurrentUpdate = persistenceError {
                    conflicts += 1
                } else {
                    Issue.record("Unexpected concurrent update error: \(error)")
                }
            }
        }
        #expect(successes == 1)
        #expect(conflicts == 1)
    }

    @Test
    func propagatesResumeAndIntegrityPersistenceFailures() async throws {
        let missing = FailingLedgerStore(
            error: .resumeTargetNotFound(runID: "run-missing")
        )
        await #expect(throws: FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: "run-missing")) {
            try await FlowRunLedgerCoordinator(persistence: missing).load(
                runID: "run-missing"
            )
        }

        let integrity = FailingLedgerStore(
            error: .artifactIntegrityFailure(path: "report.json", reason: "digest mismatch")
        )
        await #expect(throws: FlowRunLedgerPersistenceError.artifactIntegrityFailure(
            path: "report.json",
            reason: "digest mismatch"
        )) {
            try await FlowRunLedgerCoordinator(persistence: integrity).load(
                runID: "run-integrity"
            )
        }
    }

    private func artifactReference(id: String, path: String) throws -> ArtifactReference {
        ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "0", count: 64)
            ),
            byteCount: 0
        )
    }

    private static func progressEvent(sequence: Int) -> FlowRunProgressEvent {
        FlowRunProgressEvent(
            runID: "run-concurrent",
            sequence: sequence,
            kind: .runStarted,
            runStatus: .running,
            message: "update"
        )
    }

    private func capture<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func makeLedger(runID: String) throws -> FlowRunLedger {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = try FlowRunManifest(
            runID: runID,
            status: .created,
            actor: FlowRunActor(kind: .system, identifier: "test"),
            createdAt: now,
            updatedAt: now
        )
        return FlowRunLedger(
            runID: runID,
            runManifest: manifest,
            stages: []
        )
    }
}

private actor CoordinatedCASLedgerStore: FlowRunLedgerPersisting {
    private var ledger: FlowRunLedger
    private var loadCount = 0
    private var firstLoadContinuation: CheckedContinuation<Void, Never>?

    init(ledger: FlowRunLedger) {
        self.ledger = ledger
    }

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        let snapshot = ledger
        loadCount += 1
        if loadCount == 1 {
            await withCheckedContinuation { continuation in
                firstLoadContinuation = continuation
            }
        } else if loadCount == 2 {
            firstLoadContinuation?.resume()
            firstLoadContinuation = nil
        }
        return snapshot
    }

    func saveRunLedger(_ proposed: FlowRunLedger) async throws {
        let expected = ledger.runManifest.revision + 1
        guard proposed.runManifest.revision == expected else {
            throw FlowRunLedgerPersistenceError.concurrentUpdate(
                runID: proposed.runID,
                expectedRevision: expected,
                actualRevision: proposed.runManifest.revision
            )
        }
        ledger = proposed
    }
}

private struct FailingLedgerStore: FlowRunLedgerPersisting {
    let error: FlowRunLedgerPersistenceError

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        throw error
    }

    func saveRunLedger(_ ledger: FlowRunLedger) async throws {
        throw error
    }
}

private actor InMemoryLedgerStore: FlowRunLedgerPersisting {
    private var ledger: FlowRunLedger
    private(set) var saveCount = 0

    init(ledger: FlowRunLedger) {
        self.ledger = ledger
    }

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        ledger
    }

    func saveRunLedger(_ ledger: FlowRunLedger) async throws {
        self.ledger = ledger
        saveCount += 1
    }
}

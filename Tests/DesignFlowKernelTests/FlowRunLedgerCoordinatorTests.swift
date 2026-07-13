import Foundation
import Testing
@testable import DesignFlowKernel

@Suite("FlowRunLedgerCoordinator")
struct FlowRunLedgerCoordinatorTests {
    @Test
    func serializesLoadUpdateAndSaveThroughPersistenceProtocol() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: "run-1", root: root))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)

        let updated = try await coordinator.update(
            runID: "run-1",
            projectRoot: root
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
        let persisted = try await coordinator.load(runID: "run-1", projectRoot: root)
        #expect(persisted == updated)
        #expect(await store.saveCount == 1)
    }

    @Test
    func rejectsRunIdentifierMismatchBeforeSaving() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: "run-1", root: root))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)

        await #expect(throws: FlowRunLedgerPersistenceError.runIdentifierMismatch(
            requested: "run-2",
            stored: "run-1"
        )) {
            try await coordinator.update(runID: "run-2", projectRoot: root) { _ in }
        }
        #expect(await store.saveCount == 0)
    }

    private func makeLedger(runID: String, root: URL) throws -> FlowRunLedger {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = try XcircuiteRunManifest(
            runID: runID,
            status: .created,
            actor: XcircuiteRunActionActor(kind: .system, identifier: "test"),
            createdAt: now,
            updatedAt: now
        )
        return FlowRunLedger(
            runID: runID,
            runDirectory: root.appending(path: ".xcircuite/runs/\(runID)"),
            runManifest: manifest,
            stages: []
        )
    }
}

private actor InMemoryLedgerStore: FlowRunLedgerPersisting {
    private var ledger: FlowRunLedger
    private(set) var saveCount = 0

    init(ledger: FlowRunLedger) {
        self.ledger = ledger
    }

    func loadRunLedger(runID: String, projectRoot: URL) async throws -> FlowRunLedger {
        ledger
    }

    func saveRunLedger(_ ledger: FlowRunLedger, projectRoot: URL) async throws {
        self.ledger = ledger
        saveCount += 1
    }
}

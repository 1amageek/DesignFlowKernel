import CircuiteFoundation
import Foundation
import Testing
@testable import DesignFlowKernel

@Suite("FlowRunLedgerCoordinator")
struct FlowRunLedgerCoordinatorTests {
    @Test
    func createRejectsLifecycleDataWithTypedIssue() async throws {
        var ledger = try makeLedger(runID: "run-invalid-create")
        ledger.stages = [FlowStageResult(stageID: "simulation", status: .succeeded)]
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: "unused"))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)

        await #expect(throws: FlowRunLedgerPersistenceError.invalidInitialProjection(
            runID: "run-invalid-create",
            issue: .containsLifecycleProjection
        )) {
            try await coordinator.create(ledger)
        }
        #expect(await store.saveCount == 0)
    }

    @Test
    func atomicCreationRejectsOneOfTwoConcurrentCreators() async throws {
        let store = AtomicCreationLedgerStore()
        let first = FlowRunLedgerCoordinator(persistence: store)
        let second = FlowRunLedgerCoordinator(persistence: store)
        let ledger = try makeLedger(runID: "run-concurrent-create")

        async let firstCreation = capture {
            try await first.create(ledger)
        }
        async let secondCreation = capture {
            try await second.create(ledger)
        }

        var successes = 0
        var conflicts = 0
        for result in await [firstCreation, secondCreation] {
            switch result {
            case .success:
                successes += 1
            case .failure(let error):
                if let persistenceError = error as? FlowRunLedgerPersistenceError,
                   persistenceError == .runAlreadyExists(runID: ledger.runID) {
                    conflicts += 1
                } else {
                    Issue.record("Unexpected concurrent creation error: \(error)")
                }
            }
        }

        #expect(successes == 1)
        #expect(conflicts == 1)
        #expect(await store.storedLedger == ledger)
    }

    @Test
    func artifactMergeKeepsStageLocalIdentifiersAndRejectsLocatorConflicts() throws {
        let first = try artifactReference(
            id: "stage-summary",
            path: "runs/run-1/stages/001-drc/summary.json"
        )
        let second = try artifactReference(
            id: "stage-summary",
            path: "runs/run-1/stages/002-lvs/summary.json"
        )

        let merged = try mergedArtifactReferences([first, second, first])
        #expect(merged.count == 2)
        #expect(Set(merged.map(\.locator.location)) == Set([
            first.locator.location,
            second.locator.location,
        ]))

        let conflicting = ArtifactReference(
            id: first.id,
            locator: first.locator,
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "1", count: 64)
            ),
            byteCount: 1
        )
        #expect(throws: FlowExecutionError.conflictingArtifactReference(
            artifactID: first.id.rawValue,
            location: first.locator.location.value
        )) {
            _ = try mergedArtifactReferences([first, conflicting])
        }
    }

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
    func startsAndFinalizesCompleteLifecycle() async throws {
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

        let succeeded = try await coordinator.finalize(
            runID: "run-lifecycle",
            status: .succeeded,
            stages: [FlowStageResult(stageID: "simulation", status: .succeeded)],
            toolchain: toolchainManifest(runID: "run-lifecycle", stageID: "simulation"),
            evidence: try evidenceManifest(artifacts: []),
            artifacts: [],
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
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let blockedManifest = try FlowRunManifest(
            runID: "run-review",
            status: .blocked,
            actor: FlowRunActor(kind: .system, identifier: "test"),
            createdAt: timestamp,
            updatedAt: timestamp,
            startedAt: timestamp,
            finishedAt: timestamp
        )
        let store = InMemoryLedgerStore(ledger: FlowRunLedger(
            runID: "run-review",
            runManifest: blockedManifest,
            stages: [FlowStageResult(stageID: "review", status: .blocked)]
        ))
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
        let cancelled = try await coordinator.finalize(
            runID: "run-cancel",
            status: .cancelled,
            stages: [FlowStageResult(
                stageID: "run",
                status: .blocked,
                gates: [FlowGateResult(gateID: "cancellation", status: .blocked)]
            )],
            toolchain: toolchainManifest(runID: "run-cancel", stageID: "run"),
            evidence: try evidenceManifest(artifacts: []),
            artifacts: []
        )
        #expect(cancelled.runManifest.status == .cancelled)
        #expect(cancelled.cancellationRequest == request)
        #expect(cancelled.runManifest.finishedAt != nil)
    }

    @Test
    func rejectsTerminalStateThroughNonterminalTransitionAPI() async throws {
        let runID = "run-terminal-bypass"
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: runID))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        _ = try await coordinator.transition(runID: runID, to: .running)

        await #expect(throws: FlowRunLedgerPersistenceError.invalidTransition(
            runID: runID,
            from: "nonterminal-transition-api",
            to: FlowRunStatus.failed.rawValue
        )) {
            try await coordinator.transition(runID: runID, to: .failed)
        }
        #expect(await store.saveCount == 1)
    }

    @Test
    func finalizesAConsistentTerminalProjectionAtomically() async throws {
        let runID = "run-atomic-finalize"
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: runID))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        _ = try await coordinator.transition(runID: runID, to: .running)
        let artifact = try artifactReference(
            id: "result",
            path: ".xcircuite/runs/\(runID)/result.json"
        )
        let evidence = try evidenceManifest(artifacts: [artifact])

        let finalized = try await coordinator.finalize(
            runID: runID,
            status: .succeeded,
            stages: [FlowStageResult(stageID: "simulation", status: .succeeded)],
            toolchain: toolchainManifest(runID: runID, stageID: "simulation"),
            evidence: evidence,
            artifacts: [artifact]
        )

        #expect(finalized.runManifest.status == .succeeded)
        #expect(finalized.stages.first?.status == .succeeded)
        #expect(finalized.evidence == evidence)
        #expect(finalized.artifacts == [artifact])
    }

    @Test
    func finalizesOutputToInputHandoffAtSharedPhysicalLocation() async throws {
        let runID = "run-shared-handoff"
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: runID))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        _ = try await coordinator.transition(runID: runID, to: .running)
        let path = ".storage/runs/\(runID)/waveforms/pre-simulation.json"
        let output = try artifactReference(id: "pre-simulation-waveform", path: path)
        let input = try artifactReference(
            id: "post-layout-waveform-input",
            path: path,
            role: .input
        )
        let artifacts = [output, input]

        let finalized = try await coordinator.finalize(
            runID: runID,
            status: .succeeded,
            stages: [
                FlowStageResult(
                    stageID: "pre-simulation",
                    status: .succeeded,
                    artifacts: [output]
                ),
                FlowStageResult(
                    stageID: "post-layout-comparison",
                    status: .succeeded,
                    artifacts: [input]
                ),
            ],
            toolchain: FlowToolchainManifest(
                runID: runID,
                stages: [
                    FlowToolchainStageRecord(
                        stageID: "pre-simulation",
                        executorToolID: "simulation-tool"
                    ),
                    FlowToolchainStageRecord(
                        stageID: "post-layout-comparison",
                        executorToolID: "comparison-tool"
                    ),
                ]
            ),
            evidence: try evidenceManifest(artifacts: artifacts),
            artifacts: artifacts
        )

        #expect(finalized.artifacts.count == 2)
        #expect(Set(finalized.artifacts.map(\.locator.location)).count == 1)
        #expect(Set(finalized.artifacts.map(\.locator.role)) == Set([.output, .input]))
    }

    @Test
    func rejectsInconsistentTerminalProjectionBeforeSaving() async throws {
        let runID = "run-invalid-finalize"
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: runID))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        _ = try await coordinator.transition(runID: runID, to: .running)
        let evidence = try evidenceManifest(artifacts: [])

        await #expect(throws: FlowRunLedgerPersistenceError.invalidTerminalProjection(
            runID: runID,
            issue: .succeededRunContainsUnsuccessfulStage
        )) {
            try await coordinator.finalize(
                runID: runID,
                status: .succeeded,
                stages: [FlowStageResult(
                    stageID: "simulation",
                    status: .failed,
                    diagnostics: [FlowDiagnostic(
                        severity: .error,
                        code: "FAILED",
                        message: "failed"
                    )]
                )],
                toolchain: toolchainManifest(runID: runID, stageID: "simulation"),
                evidence: evidence,
                artifacts: []
            )
        }
        #expect(await store.saveCount == 1)
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
    func rejectsMutationOfKernelOwnedTerminalProjection() async throws {
        let runID = "run-protected-projection"
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: runID))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)

        await #expect(throws: FlowRunLedgerPersistenceError.protectedProjectionMutation(
            runID: runID,
            field: "stages"
        )) {
            try await coordinator.update(runID: runID) {
                $0.stages.append(FlowStageResult(stageID: "bypass", status: .succeeded))
            }
        }
        #expect(await store.saveCount == 0)
    }

    @Test
    func terminalRunAcceptsTypedAppendOnlySuggestedActionSelection() async throws {
        let runID = "run-terminal-decision"
        let store = InMemoryLedgerStore(ledger: try makeLedger(runID: runID))
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        _ = try await coordinator.transition(runID: runID, to: .running)
        _ = try await coordinator.finalize(
            runID: runID,
            status: .succeeded,
            stages: [FlowStageResult(stageID: "simulation", status: .succeeded)],
            toolchain: toolchainManifest(runID: runID, stageID: "simulation"),
            evidence: try evidenceManifest(artifacts: []),
            artifacts: []
        )
        let action = FlowRunActionRecord(
            actionID: "select-review-action",
            runID: runID,
            actor: FlowRunActor(kind: .human, identifier: "reviewer"),
            actionKind: FlowRunSuggestedActionSelection.actionKind,
            status: .succeeded,
            context: FlowRunActionContext(
                suggestedAction: FlowRunActionContext.SuggestedAction(
                    nextActionID: "review-failure",
                    nextActionKind: "review",
                    action: FlowRunSuggestedAction(
                        id: "review-failure",
                        readiness: .ready,
                        operation: .reviewRun,
                        runID: runID,
                        reason: "Review the terminal failure evidence."
                    )
                )
            )
        )

        let updated = try await coordinator.appendAction(action)

        #expect(updated.actions == [action])
        #expect(updated.suggestedActionSelections.count == 1)
        #expect(updated.suggestedActionSelections.first?.actionRecordID == action.actionID)
        #expect(updated.evidence?.artifacts == [])

        let repeated = try await coordinator.appendAction(action)
        #expect(repeated == updated)

        await #expect(throws: FlowRunLedgerPersistenceError.duplicateActionID(
            runID: runID,
            actionID: action.actionID
        )) {
            try await coordinator.appendAction(
                FlowRunActionRecord(
                    actionID: action.actionID,
                    runID: runID,
                    actor: action.actor,
                    actionKind: action.actionKind,
                    status: .failed,
                    context: action.context,
                    createdAt: action.createdAt
                )
            )
        }

        let unretainedOutput = try artifactReference(
            id: "unretained-output",
            path: "runs/\(runID)/actions/unretained-output.json"
        )
        await #expect(throws: FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
            runID: runID,
            path: unretainedOutput.path
        )) {
            try await coordinator.appendAction(FlowRunActionRecord(
                actionID: "bind-unretained-output",
                runID: runID,
                actor: FlowRunActor(kind: .agent, identifier: "agent"),
                actionKind: "analysis.bind-output",
                status: .succeeded,
                outputs: [unretainedOutput]
            ))
        }

        await #expect(throws: FlowRunLedgerPersistenceError.protectedProjectionMutation(
            runID: runID,
            field: "actions"
        )) {
            try await coordinator.update(runID: runID) { ledger in
                ledger.actions.removeAll()
                ledger.suggestedActionSelections.removeAll()
            }
        }
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

    private func artifactReference(
        id: String,
        path: String,
        role: ArtifactRole = .output
    ) throws -> ArtifactReference {
        ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: role,
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

    private func evidenceManifest(artifacts: [ArtifactReference]) throws -> EvidenceManifest {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_100)
        return EvidenceManifest(
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "ledger-test",
                    version: "1"
                ),
                startedAt: timestamp,
                completedAt: timestamp
            ),
            artifacts: artifacts
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

private func toolchainManifest(
    runID: String,
    stageID: String
) -> FlowToolchainManifest {
    FlowToolchainManifest(
        runID: runID,
        stages: [
            FlowToolchainStageRecord(
                stageID: stageID,
                executorToolID: "test-tool"
            ),
        ]
    )
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

    func saveRunLedger(_ proposed: FlowRunLedger) async throws -> FlowRunLedger {
        let expected = ledger.runManifest.revision + 1
        guard proposed.runManifest.revision == expected else {
            throw FlowRunLedgerPersistenceError.concurrentUpdate(
                runID: proposed.runID,
                expectedRevision: expected,
                actualRevision: proposed.runManifest.revision
            )
        }
        ledger = proposed
        return proposed
    }

    func createRunLedger(_ proposed: FlowRunLedger) async throws -> FlowRunLedger {
        throw FlowRunLedgerPersistenceError.runAlreadyExists(runID: proposed.runID)
    }
}

private actor AtomicCreationLedgerStore: FlowRunLedgerPersisting {
    private(set) var storedLedger: FlowRunLedger?

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        guard let storedLedger, storedLedger.runID == runID else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        }
        return storedLedger
    }

    func createRunLedger(_ ledger: FlowRunLedger) async throws -> FlowRunLedger {
        guard storedLedger == nil else {
            throw FlowRunLedgerPersistenceError.runAlreadyExists(runID: ledger.runID)
        }
        storedLedger = ledger
        return ledger
    }

    func saveRunLedger(_ ledger: FlowRunLedger) async throws -> FlowRunLedger {
        guard storedLedger != nil else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: ledger.runID)
        }
        storedLedger = ledger
        return ledger
    }
}

private struct FailingLedgerStore: FlowRunLedgerPersisting {
    let error: FlowRunLedgerPersistenceError

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        throw error
    }

    func saveRunLedger(_ ledger: FlowRunLedger) async throws -> FlowRunLedger {
        throw error
    }

    func createRunLedger(_ ledger: FlowRunLedger) async throws -> FlowRunLedger {
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

    func saveRunLedger(_ ledger: FlowRunLedger) async throws -> FlowRunLedger {
        self.ledger = ledger
        saveCount += 1
        return ledger
    }

    func createRunLedger(_ proposed: FlowRunLedger) async throws -> FlowRunLedger {
        throw FlowRunLedgerPersistenceError.runAlreadyExists(runID: proposed.runID)
    }
}

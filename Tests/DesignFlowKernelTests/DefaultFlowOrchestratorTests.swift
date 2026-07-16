import Foundation
import DesignFlowKernel
import Testing
import ToolQualification
import DesignFlowKernel

@Suite("Default flow orchestrator")
struct DefaultFlowOrchestratorTests {
    @Test func successfulFlowPersistsStageResultsAndRunManifest() async throws {
        let root = try makeTemporaryRoot("success")
        defer { removeTemporaryRoot(root) }

        let request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-1",
            intent: "Run basic flow",
            stages: [
                FlowStageDefinition(stageID: "001-preflight", displayName: "Preflight"),
                FlowStageDefinition(stageID: "002-drc", displayName: "DRC"),
            ]
        )

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                StubStageExecutor(stageID: "001-preflight", toolID: "preflight-tool", status: .succeeded),
                StubStageExecutor(stageID: "002-drc", toolID: "drc-tool", status: .succeeded),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(result.stages.map(\.stageID) == ["001-preflight", "002-drc"])
        #expect(fileExists(".xcircuite/runs/run-1/stages/001-preflight/result.json", in: root))
        #expect(fileExists(".xcircuite/runs/run-1/stages/002-drc/result.json", in: root))

        let runManifest = try await TestFlowInfrastructure.bound(to: root).readJSON(
            FlowRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(runManifest.runID == "run-1")
        #expect(runManifest.status == .succeeded)
        #expect(runManifest.intent == "Run basic flow")
        #expect(runManifest.actor.identifier == "design-flow-kernel")
        #expect(runManifest.startedAt != nil)
        #expect(runManifest.finishedAt != nil)
        #expect(runManifest.revision >= 2)

        let toolchain = try await readToolchainManifest(in: root, runID: "run-1")
        #expect(toolchain.runID == "run-1")
        #expect(toolchain.stages.map(\.stageID) == ["001-preflight", "002-drc"])
        #expect(toolchain.stages.allSatisfy { $0.requiredTool == nil })
        #expect(toolchain.stages.allSatisfy { $0.selectedToolID == nil })
        _ = try await assertToolchainArtifact(in: root, runID: "run-1")
    }

    @Test func successfulFlowPersistsProgressEventsForReview() async throws {
        let root = try makeTemporaryRoot("progress")
        defer { removeTemporaryRoot(root) }

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-progress",
                intent: "Run with progress ledger",
                stages: [
                    FlowStageDefinition(stageID: "001-preflight", displayName: "Preflight"),
                    FlowStageDefinition(stageID: "002-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                StubStageExecutor(stageID: "001-preflight", toolID: "preflight-tool", status: .succeeded),
                StubStageExecutor(stageID: "002-drc", toolID: "drc-tool", status: .succeeded),
            ]
        )

        #expect(result.status == .succeeded)
        let ledger = try await TestFlowInfrastructure.bound(to: root).loadRunLedger(runID: "run-progress")
        #expect(ledger.progressEvents.map(\.kind) == [
            .runStarted,
            .stageStarted,
            .stageFinished,
            .stageStarted,
            .stageFinished,
            .runFinished,
        ])

        let summary = DefaultFlowRunLedgerSummarizer().summarize(ledger)
        #expect(summary.progressEventCount == 6)
        #expect(summary.latestProgressEvent?.kind == .runFinished)

        let manifest = try await TestFlowInfrastructure.bound(to: root).readJSON(
            FlowRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-progress/manifest.json")
        )
        #expect(manifest.artifacts.contains {
            $0.artifactID == "run-progress"
                && $0.path == ".xcircuite/runs/run-progress/progress.jsonl"
                && $0.format == .text
        })

        let bundle = try await makeTestReviewBundler(projectRoot: root).makeReviewBundle(
            runID: "run-progress",
            projectRoot: root
        )
        #expect(bundle.artifacts.contains {
            $0.purpose == .runProgress
                && $0.reference.path == ".xcircuite/runs/run-progress/progress.jsonl"
        })
    }

    @Test func successfulFlowPersistsToolchainProfileInPlanManifestAndSummary() async throws {
        let root = try makeTemporaryRoot("toolchain-profile")
        defer { removeTemporaryRoot(root) }

        let profile = FlowToolchainProfileRecord(
            profileID: "local-signoff",
            pdkID: "test-pdk",
            technologyCatalogID: "test-catalog",
            technologyCatalogPath: "tech/catalog.json",
            profileArtifactPath: ".xcircuite/runs/run-profile/toolchain-profile.json",
            drcTechnologyInput: .path("tech/drc.json"),
            lvsTechnologyInput: .path("tech/lvs.json"),
            pexTechnology: .jsonFile(path: "tech/pex.json"),
            metadata: ["source": "unit-test"]
        )
        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-profile",
                intent: "Run with toolchain profile",
                toolchainProfile: profile,
                stages: [
                    FlowStageDefinition(stageID: "001-preflight", displayName: "Preflight"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                StubStageExecutor(stageID: "001-preflight", toolID: "preflight-tool", status: .succeeded),
            ]
        )

        #expect(result.status == .succeeded)
        let plan = try await TestFlowInfrastructure.bound(to: root).readJSON(
            FlowRunPlan.self,
            from: root.appending(path: ".xcircuite/runs/run-profile/plan.json")
        )
        #expect(plan.toolchainProfile == profile)

        let toolchain = try await readToolchainManifest(in: root, runID: "run-profile")
        #expect(toolchain.profile == profile)

        let summary = try await makeTestLedgerInspector(projectRoot: root).inspectRun(
            runID: "run-profile",
            projectRoot: root
        )
        #expect(summary.toolchain?.profileID == "local-signoff")
        #expect(summary.toolchain?.pdkID == "test-pdk")
        #expect(summary.toolchain?.technologyCatalogID == "test-catalog")
        #expect(summary.toolchain?.technologyCatalogPath == "tech/catalog.json")
        #expect(summary.toolchain?.profileArtifactPath == ".xcircuite/runs/run-profile/toolchain-profile.json")
    }

    @Test func progressSubscriberReturnsSnapshotAfterCursor() async throws {
        let root = try makeTemporaryRoot("progress-snapshot")
        defer { removeTemporaryRoot(root) }

        _ = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-progress-snapshot",
                intent: "Run with progress snapshot",
                stages: [
                    FlowStageDefinition(stageID: "001-preflight", displayName: "Preflight"),
                    FlowStageDefinition(stageID: "002-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                StubStageExecutor(stageID: "001-preflight", toolID: "preflight-tool", status: .succeeded),
                StubStageExecutor(stageID: "002-drc", toolID: "drc-tool", status: .succeeded),
            ]
        )

        let snapshot = try await makeTestProgressSubscriber(projectRoot: root).snapshot(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: "run-progress-snapshot",
                afterSequence: 1
            )
        )

        #expect(snapshot.afterSequence == 1)
        #expect(snapshot.latestSequence == 6)
        #expect(snapshot.events.map(\.sequence) == [2, 3, 4, 5, 6])
        #expect(snapshot.terminalStatus == .succeeded)
        #expect(snapshot.isTerminal)
    }

    @Test func progressStoreAppendsLongDurationStressLedgerWithoutReplayingHistory() async throws {
        let root = try makeTemporaryRoot("progress-stress")
        defer { removeTemporaryRoot(root) }

        let runID = "run-progress-stress"
        let infrastructure = await TestFlowInfrastructure.bound(to: root)
        let store = FlowRunProgressStore(persistence: infrastructure)
        let stressEventCount = 640
        try await store.appendEvent(
            runID: runID,
            kind: .runStarted,
            runStatus: .running,
            message: "Run started."
        )
        for index in 1...stressEventCount {
            let kind: FlowRunProgressEventKind = index.isMultiple(of: 2) ? .stageFinished : .stageStarted
            let status: FlowStageStatus = index.isMultiple(of: 2) ? .succeeded : .running
            try await store.appendEvent(
                runID: runID,
                kind: kind,
                stageID: "stress-stage-\(index)",
                stageStatus: status,
                runStatus: .running,
                message: "Stress progress event \(index)."
            )
        }
        try await store.appendEvent(
            runID: runID,
            kind: .runFinished,
            runStatus: .succeeded,
            message: "Run succeeded."
        )

        let fullSnapshot = try await makeTestProgressSubscriber(projectRoot: root).snapshot(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: runID
            )
        )
        let expectedSequenceCount = stressEventCount + 2
        #expect(fullSnapshot.events.count == expectedSequenceCount)
        #expect(fullSnapshot.events.map(\.sequence) == Array(1...expectedSequenceCount))
        #expect(fullSnapshot.latestSequence == expectedSequenceCount)
        #expect(fullSnapshot.terminalStatus == .succeeded)
        #expect(fullSnapshot.isTerminal)

        let tailSnapshot = try await makeTestProgressSubscriber(projectRoot: root).snapshot(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: runID,
                afterSequence: stressEventCount
            )
        )
        #expect(tailSnapshot.events.map(\.sequence) == [stressEventCount + 1, stressEventCount + 2])
        #expect(tailSnapshot.events.last?.kind == .runFinished)
        #expect(tailSnapshot.terminalStatus == .succeeded)

        let artifacts = try await store.runLevelArtifacts(runID: runID)
        let expectedProgressPath = ".xcircuite/runs/\(runID)/progress.jsonl"
        let hasProgressArtifact = artifacts.contains { artifact in
            artifact.artifactID == "run-progress"
                && artifact.path == expectedProgressPath
                && artifact.byteCount > 0
        }
        #expect(hasProgressArtifact)
        try copyProgressStressArtifactIfRequested(root: root, runID: runID)
    }

    @Test func progressSubscriberEmitsSnapshot() async throws {
        let root = try makeTemporaryRoot("progress-cli-snapshot")
        defer { removeTemporaryRoot(root) }

        _ = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-progress-cli",
                intent: "Run with CLI progress snapshot",
                stages: [
                    FlowStageDefinition(stageID: "001-preflight", displayName: "Preflight"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                StubStageExecutor(stageID: "001-preflight", toolID: "preflight-tool", status: .succeeded),
            ]
        )

        let snapshot = try await makeTestProgressSubscriber(projectRoot: root).snapshot(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: "run-progress-cli",
                afterSequence: 2
            )
        )

        #expect(snapshot.events.map(\.kind) == [.stageFinished, .runFinished])
        #expect(snapshot.terminalStatus == .succeeded)
    }

    @Test func progressSubscriberFollowsNewEvents() async throws {
        let root = try makeTemporaryRoot("progress-cli-follow")
        defer { removeTemporaryRoot(root) }

        let sink = ProgressLineSink()

        async let followResult = makeTestProgressSubscriber(projectRoot: root).followProgress(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: "run-progress-follow",
                waitForNewEvents: true,
                timeoutMilliseconds: 1_000,
                pollIntervalMilliseconds: 10
            )
        ) { event in
            await sink.append(event)
        }

        let progressStore = FlowRunProgressStore(persistence: await TestFlowInfrastructure.bound(to: root))
        try await progressStore.appendEvent(
            runID: "run-progress-follow",
            kind: .runStarted,
            runStatus: .running,
            message: "Run started."
        )
        try await progressStore.appendEvent(
            runID: "run-progress-follow",
            kind: .runFinished,
            runStatus: .succeeded,
            message: "Run succeeded."
        )

        let result = try await followResult
        #expect(result.isTerminal)

        let events = await sink.events()

        #expect(events.map(\.kind) == [.runStarted, .runFinished])
        #expect(events.last?.runStatus == .succeeded)
    }

    @Test func progressFollowRecoversRetryEventsAfterCursor() async throws {
        let root = try makeTemporaryRoot("progress-retry-follow")
        defer { removeTemporaryRoot(root) }

        let sink = ProgressLineSink()
        async let followResult = makeTestProgressSubscriber(projectRoot: root).followProgress(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: "run-progress-retry",
                waitForNewEvents: true,
                timeoutMilliseconds: 2_000,
                pollIntervalMilliseconds: 10
            )
        ) { event in
            await sink.append(event)
        }

        let script = StageResultScript(results: [
            FlowStageResult(
                stageID: "001-drc",
                status: .failed,
                diagnostics: [
                    FlowDiagnostic(
                        severity: .error,
                        code: "TRANSIENT_TOOL_FAILURE",
                        message: "Temporary tool failure."
                    ),
                ]
            ),
            FlowStageResult(stageID: "001-drc", status: .succeeded),
        ])

        let runResult = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-progress-retry",
                intent: "Run progress follow over retry",
                stages: [
                    FlowStageDefinition(
                        stageID: "001-drc",
                        displayName: "DRC",
                        retryPolicy: FlowStageRetryPolicy(
                            maxAttempts: 2,
                            retryableDiagnosticCodes: ["TRANSIENT_TOOL_FAILURE"]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DelayedScriptedStageExecutor(
                    stageID: "001-drc",
                    toolID: "drc-tool",
                    script: script,
                    delayNanoseconds: 25_000_000
                ),
            ]
        )

        #expect(runResult.status == .succeeded)
        #expect(await script.executionCount() == 2)

        let result = try await followResult
        #expect(result.isTerminal)
        let events = await sink.events()

        #expect(events.map(\.kind) == [
            .runStarted,
            .stageStarted,
            .stageRetryScheduled,
            .stageStarted,
            .stageFinished,
            .runFinished,
        ])
        #expect(events.map(\.sequence) == [1, 2, 3, 4, 5, 6])
        #expect(events[2].stageID == "001-drc")
        #expect(events[2].stageStatus == .failed)
        #expect(events.last?.runStatus == .succeeded)

        let recovered = try await makeTestProgressSubscriber(projectRoot: root).snapshot(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: "run-progress-retry",
                afterSequence: 2
            )
        )
        #expect(recovered.events.map(\.kind) == [
            .stageRetryScheduled,
            .stageStarted,
            .stageFinished,
            .runFinished,
        ])
        #expect(recovered.latestSequence == 6)
        #expect(recovered.terminalStatus == .succeeded)
        #expect(recovered.isTerminal)
    }

    @Test func cancellationRecorderStopsRunBeforeNextStageAndIsReviewable() async throws {
        let root = try makeTemporaryRoot("cancel")
        defer { removeTemporaryRoot(root) }

        let cancellation = try await makeTestCancellationRecorder(projectRoot: root).requestCancellation(
            projectRoot: root,
            runID: "run-cancel",
            requestedBy: "reviewer-1",
            reason: "stop before signoff"
        )
        #expect(cancellation.status == "recorded")

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-cancel",
                intent: "Run cancelled by reviewer",
                stages: [
                    FlowStageDefinition(stageID: "001-drc", displayName: "DRC"),
                ],
                allowExistingRunDirectory: true
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                ThrowingStageExecutor(stageID: "001-drc", toolID: "drc-tool"),
            ]
        )

        #expect(result.status == .cancelled)
        let stage = try #require(result.stages.first)
        #expect(stage.status == .blocked)
        #expect(stage.gates.contains { $0.gateID == "cancellation" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "RUN_CANCELLATION_REQUESTED" })

        let summary = try await makeTestLedgerInspector(projectRoot: root).inspectRun(
            runID: "run-cancel",
            projectRoot: root
        )
        #expect(summary.status == .cancelled)
        #expect(summary.cancellationRequest?.requestedBy == "reviewer-1")
        #expect(summary.nextActions.contains { $0.kind == "reviewCancellation" })

        let bundle = try await makeTestReviewBundler(projectRoot: root).makeReviewBundle(
            runID: "run-cancel",
            projectRoot: root
        )
        #expect(bundle.reviewItems.contains {
            $0.kind == .cancellation && $0.status == .informational
        })
        #expect(bundle.artifacts.contains {
            $0.purpose == .runCancellationRequest
                && $0.reference.path == ".xcircuite/runs/run-cancel/cancellation.json"
        })
    }

    @Test func executorCooperativeCancellationStopsRunDuringStage() async throws {
        let root = try makeTemporaryRoot("cooperative-cancel")
        defer { removeTemporaryRoot(root) }

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-cooperative-cancel",
                intent: "Run cancelled during long stage",
                stages: [
                    FlowStageDefinition(stageID: "001-long-drc", displayName: "Long DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                CooperativeCancellationStageExecutor(
                    stageID: "001-long-drc",
                    toolID: "long-drc-tool"
                ),
            ]
        )

        #expect(result.status == .cancelled)
        let stage = try #require(result.stages.first)
        #expect(stage.status == .blocked)
        #expect(stage.gates.contains { $0.gateID == "cancellation" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "RUN_CANCELLATION_REQUESTED" })

        let ledger = try await TestFlowInfrastructure.bound(to: root).loadRunLedger(
            runID: "run-cooperative-cancel"
        )
        #expect(ledger.cancellationRequest?.requestedBy == "long-drc-tool")
        #expect(ledger.progressEvents.map(\.kind) == [
            .runStarted,
            .stageStarted,
            .cancellationRequested,
            .cancellationObserved,
            .runFinished,
        ])

        let summary = DefaultFlowRunLedgerSummarizer().summarize(ledger)
        #expect(summary.status == .cancelled)
        #expect(summary.nextActions.contains { $0.kind == "reviewCancellation" })
        #expect(summary.latestProgressEvent?.kind == .runFinished)

        let bundle = try await makeTestReviewBundler(projectRoot: root).makeReviewBundle(
            runID: "run-cooperative-cancel",
            projectRoot: root
        )
        #expect(bundle.artifacts.contains { $0.purpose == .runCancellationRequest })
        #expect(bundle.reviewItems.contains { $0.kind == .cancellation })
    }

    @Test func stageBlocksWhenNoEligibleToolExists() async throws {
        let root = try makeTemporaryRoot("blocked")
        defer { removeTemporaryRoot(root) }

        let request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-1",
            intent: "Run DRC",
            stages: [
                FlowStageDefinition(
                    stageID: "001-drc",
                    displayName: "DRC",
                    requiredTool: drcRequirement()
                ),
            ]
        )

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
            ]
        )

        #expect(result.status == .blocked)
        #expect(result.stages.count == 1)
        #expect(result.stages[0].diagnostics.contains { $0.code == "NO_ELIGIBLE_TOOL" })
        #expect(fileExists(".xcircuite/runs/run-1/stages/001-drc/result.json", in: root))
    }

    @Test func eligibleToolAllowsStageExecution() async throws {
        let root = try makeTemporaryRoot("tool")
        defer { removeTemporaryRoot(root) }

        let descriptor = drcDescriptor()
        let request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-1",
            intent: "Run DRC",
            stages: [
                FlowStageDefinition(
                    stageID: "001-drc",
                    displayName: "DRC",
                    requiredTool: drcRequirement()
                ),
            ]
        )

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: request,
            toolRegistry: ToolRegistry(descriptors: [descriptor]),
            healthResults: [
                descriptor.toolID: ToolHealthCheckResult(
                    toolID: descriptor.toolID,
                    status: .passed,
                    evidence: [qualifiedCorpusEvidence()]
                ),
            ],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(result.stages[0].status == .succeeded)
    }

    @Test func toolTrustGateIsPersistedWithSelectedTool() async throws {
        let root = try makeTemporaryRoot("tool-gate")
        defer { removeTemporaryRoot(root) }

        let descriptor = drcDescriptor()
        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-1",
                intent: "Run DRC with evidence gate",
                stages: [
                    FlowStageDefinition(
                        stageID: "001-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(requiredEvidenceKinds: [.corpus])
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [descriptor]),
            healthResults: [
                descriptor.toolID: ToolHealthCheckResult(
                    toolID: descriptor.toolID,
                    status: .passed,
                    evidence: [qualifiedCorpusEvidence()]
                ),
            ],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
            ]
        )

        let persisted = try await TestFlowInfrastructure.bound(to: root).readJSON(
            FlowStageResult.self,
            from: root.appending(path: ".xcircuite/runs/run-1/stages/001-drc/result.json")
        )
        #expect(result.status == .succeeded)
        #expect(result.stages[0].gates.contains {
            $0.gateID == "tool-trust" && $0.status == .passed
        })
        #expect(result.stages[0].diagnostics.contains { $0.code == "TOOL_SELECTED" })
        #expect(persisted.gates.contains { $0.gateID == "tool-trust" && $0.status == .passed })
        #expect(persisted.diagnostics.contains { $0.code == "TOOL_SELECTED" })

        let toolchain = try await readToolchainManifest(in: root, runID: "run-1")
        #expect(toolchain.schemaVersion == 1)
        #expect(toolchain.runID == "run-1")
        let record = try #require(toolchain.stages.first)
        #expect(record.stageID == "001-drc")
        #expect(record.executorToolID == "native-drc")
        #expect(record.requiredTool?.requiredEvidenceKinds == [.corpus])
        #expect(record.selectedToolID == "native-drc")
        #expect(record.selectedDescriptor?.toolID == "native-drc")
        #expect(record.selectedDecision?.status == .eligible)
        #expect(record.selectedHealth?.evidence.contains {
            $0.evidenceID == "corpus-1" && $0.kind == .corpus
        } == true)
        let evaluation = try #require(record.evaluations.first)
        #expect(evaluation.descriptor.toolID == "native-drc")
        #expect(evaluation.decision.status == .eligible)
        #expect(evaluation.health?.evidence.contains { $0.kind == .corpus } == true)
        _ = try await assertToolchainArtifact(in: root, runID: "run-1")
    }

    @Test func stageBlocksWhenRequiredEvidenceIsMissing() async throws {
        let root = try makeTemporaryRoot("tool-evidence-missing")
        defer { removeTemporaryRoot(root) }

        let descriptor = drcDescriptor()
        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-1",
                intent: "Run DRC with missing evidence",
                stages: [
                    FlowStageDefinition(
                        stageID: "001-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(requiredEvidenceKinds: [.corpus])
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [descriptor]),
            healthResults: [
                descriptor.toolID: ToolHealthCheckResult(
                    toolID: descriptor.toolID,
                    status: .passed,
                    evidence: [ToolEvidence(evidenceID: "smoke-1", kind: .smoke)]
                ),
            ],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
            ]
        )

        let stage = try #require(result.stages.first)
        #expect(result.status == .blocked)
        #expect(stage.diagnostics.contains { $0.code == "NO_ELIGIBLE_TOOL" })
        #expect(stage.diagnostics.contains { $0.code == "MISSING_REQUIRED_EVIDENCE" })
        #expect(stage.gates.contains { $0.gateID == "tool-trust" && $0.status == .failed })

        let toolchain = try await readToolchainManifest(in: root, runID: "run-1")
        let record = try #require(toolchain.stages.first)
        #expect(record.stageID == "001-drc")
        #expect(record.executorToolID == "native-drc")
        #expect(record.selectedToolID == nil)
        #expect(record.selectedDescriptor == nil)
        #expect(record.selectedDecision == nil)
        let evaluation = try #require(record.evaluations.first)
        #expect(evaluation.descriptor.toolID == "native-drc")
        #expect(evaluation.decision.status == .rejected)
        #expect(evaluation.decision.diagnostics.contains { $0.code == "MISSING_REQUIRED_EVIDENCE" })
        #expect(evaluation.health?.evidence.contains {
            $0.evidenceID == "smoke-1" && $0.kind == .smoke
        } == true)
        _ = try await assertToolchainArtifact(in: root, runID: "run-1")
    }

    @Test func stageBlocksWhenRequiredQualifiedEvidenceFails() async throws {
        let root = try makeTemporaryRoot("tool-qualified-evidence-failed")
        defer { removeTemporaryRoot(root) }

        let descriptor = drcDescriptor()
        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-1",
                intent: "Run DRC with qualified corpus evidence",
                stages: [
                    FlowStageDefinition(
                        stageID: "001-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(requiredQualifiedEvidenceKinds: [.corpus])
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [descriptor]),
            healthResults: [
                descriptor.toolID: ToolHealthCheckResult(
                    toolID: descriptor.toolID,
                    status: .passed,
                    evidence: [
                        ToolEvidence(
                            evidenceID: "corpus-1",
                            kind: .corpus
                        ),
                    ]
                ),
            ],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
            ]
        )

        let stage = try #require(result.stages.first)
        #expect(result.status == .blocked)
        #expect(stage.diagnostics.contains { $0.code == "NO_ELIGIBLE_TOOL" })
        #expect(stage.diagnostics.contains { $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE" })
        #expect(stage.gates.contains { $0.gateID == "tool-trust" && $0.status == .failed })

        let toolchain = try await readToolchainManifest(in: root, runID: "run-1")
        let record = try #require(toolchain.stages.first)
        #expect(record.requiredTool?.requiredQualifiedEvidenceKinds == [.corpus])
        #expect(record.selectedToolID == nil)
        let evaluation = try #require(record.evaluations.first)
        #expect(evaluation.decision.status == .rejected)
        #expect(evaluation.decision.diagnostics.contains {
            $0.code == "UNQUALIFIED_REQUIRED_EVIDENCE"
        })
        #expect(evaluation.decision.diagnostics.contains {
            $0.code == "QUALIFICATION_EVIDENCE_ARTIFACT_MISSING"
        })
    }

    @Test func stageBlocksWhenRequiredEvidenceIsStale() async throws {
        let root = try makeTemporaryRoot("tool-evidence-stale")
        defer { removeTemporaryRoot(root) }

        let descriptor = drcDescriptor()
        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-1",
                intent: "Run DRC with stale corpus evidence",
                stages: [
                    FlowStageDefinition(
                        stageID: "001-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(
                            requiredQualifiedEvidenceKinds: [.corpus],
                            maximumEvidenceAgeSeconds: 1
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [descriptor]),
            healthResults: [
                descriptor.toolID: ToolHealthCheckResult(
                    toolID: descriptor.toolID,
                    status: .passed,
                    evidence: [
                        ToolEvidence(
                            evidenceID: "corpus-1",
                            kind: .corpus,
                            checkedAt: Date(timeIntervalSince1970: 0)
                        ),
                    ]
                ),
            ],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
            ]
        )

        let stage = try #require(result.stages.first)
        #expect(result.status == .blocked)
        #expect(stage.diagnostics.contains { $0.code == "NO_ELIGIBLE_TOOL" })
        #expect(stage.diagnostics.contains { $0.code == "STALE_REQUIRED_EVIDENCE" })
        #expect(stage.gates.contains { $0.gateID == "tool-trust" && $0.status == .failed })

        let toolchain = try await readToolchainManifest(in: root, runID: "run-1")
        let record = try #require(toolchain.stages.first)
        #expect(record.requiredTool?.maximumEvidenceAgeSeconds == 1)
        #expect(record.selectedToolID == nil)
        let evaluation = try #require(record.evaluations.first)
        #expect(evaluation.decision.status == .rejected)
        #expect(evaluation.decision.diagnostics.contains {
            $0.code == "STALE_REQUIRED_EVIDENCE"
        })
    }

    @Test func runLedgerLoaderReadsStageToolchainAndApprovals() async throws {
        let root = try makeTemporaryRoot("run-ledger-loader")
        defer { removeTemporaryRoot(root) }

        let descriptor = drcDescriptor()
        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-1",
                intent: "Run DRC with human review",
                stages: [
                    FlowStageDefinition(
                        stageID: "001-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(requiredEvidenceKinds: [.corpus]),
                        requiresApproval: true
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [descriptor]),
            healthResults: [
                descriptor.toolID: ToolHealthCheckResult(
                    toolID: descriptor.toolID,
                    status: .passed,
                    evidence: [qualifiedCorpusEvidence()]
                ),
            ],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
            ]
        )
        #expect(result.status == .blocked)

        _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
            FlowGateApprovalRequest(
                projectRoot: root,
                runID: "run-1",
                stageID: "001-drc",
                verdict: .approved,
                reviewer: "reviewer-1",
                note: "approved after reviewing DRC"
            )
        )
        try await TestFlowInfrastructure.bound(to: root).writeDesignDiff(
            DesignDiff(
                runID: "run-1",
                title: "DRC review proposal",
                actor: "agent-1",
                changes: [
                    DesignDiffChange(
                        changeID: "change-1",
                        domain: .layout,
                        operation: .replace,
                        path: "/cells/INV/layout/shapes/met1/rail",
                        before: .object(["width": .number(0.14)]),
                        after: .object(["width": .number(0.20)]),
                        summary: "Widen the met1 rail for DRC review."
                    ),
                ]
            ),
            inProjectAt: root
        )
        try await TestFlowInfrastructure.bound(to: root).appendRunAction(
            FlowRunActionRecord(
                actionID: "action-1",
                runID: "run-1",
                stageID: "001-drc",
                actor: FlowRunActor(kind: .agent, identifier: "agent-1"),
                actionKind: "loadRunReview",
                status: .blocked,
                diagnostics: [
                    FlowRunDiagnostic(
                        severity: .warning,
                        code: "APPROVAL_PENDING",
                        message: "Stage awaits approval."
                    ),
                ]
            ),
            inProjectAt: root
        )

        let ledger = try await TestFlowInfrastructure.bound(to: root).loadRunLedger(runID: "run-1")
        #expect(ledger.runID == "run-1")
        #expect(ledger.runManifest.status == .blocked)
        #expect(ledger.runResult.status == .blocked)
        #expect(ledger.stages.count == 1)
        #expect(ledger.stages[0].stageID == "001-drc")
        #expect(ledger.stages[0].gates.contains {
            $0.gateID == "tool-trust" && $0.status == .passed
        })
        #expect(ledger.stages[0].gates.contains {
            $0.gateID == "approval" && $0.status == .incomplete
        })

        let toolchain = try #require(ledger.toolchain)
        let record = try #require(toolchain.stages.first)
        #expect(record.stageID == "001-drc")
        #expect(record.selectedToolID == "native-drc")
        #expect(record.selectedDecision?.status == .eligible)
        #expect(record.selectedHealth?.evidence.contains { $0.kind == .corpus } == true)
        let designDiff = try #require(ledger.designDiff)
        #expect(designDiff.runID == "run-1")
        #expect(designDiff.reviewState == .proposed)
        #expect(designDiff.changes.first?.path == "/cells/INV/layout/shapes/met1/rail")
        let action = try #require(ledger.actions.first { $0.actionID == "action-1" })
        #expect(action.actionID == "action-1")
        #expect(action.actor.kind == .agent)
        #expect(action.diagnostics.first?.code == "APPROVAL_PENDING")
        #expect(ledger.actions.contains {
            $0.actionKind == FlowRunReviewDecisionKind.approval.rawValue
                && $0.actor.kind == .human
        })

        let approval = try #require(ledger.approvals.first)
        #expect(approval.runID == "run-1")
        #expect(approval.stageID == "001-drc")
        #expect(approval.verdict == .approved)
    }

    @Test func runLedgerLoaderRejectsTerminalRunMissingPlannedStageResult() async throws {
        let root = try makeTemporaryRoot("run-ledger-missing-stage-result")
        defer { removeTemporaryRoot(root) }

        _ = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-1",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(stageID: "001-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "native-drc", status: .succeeded),
            ]
        )
        try FileManager.default.removeItem(
            at: root.appending(path: ".xcircuite/runs/run-1/stages/001-drc/result.json")
        )

        do {
            _ = try await TestFlowInfrastructure.bound(to: root).loadRunLedger(runID: "run-1")
            Issue.record("Expected missing stage result to fail closed")
        } catch {
            #expect(FileManager.default.fileExists(
                atPath: root.appending(path: ".xcircuite/runs/run-1/stages/001-drc/result.json").path()
            ) == false)
        }
    }

    @Test func runLedgerLoaderRejectsUnsafeRunID() async throws {
        let root = try makeTemporaryRoot("run-ledger-unsafe")
        defer { removeTemporaryRoot(root) }

        await #expect(throws: FlowIdentifierValidationError.self) {
            try await TestFlowInfrastructure.bound(to: root).loadRunLedger(runID: "../escape")
        }
    }

    @Test func stageBlocksWhenSelectedToolDoesNotMatchExecutorTool() async throws {
        let root = try makeTemporaryRoot("tool-mismatch")
        defer { removeTemporaryRoot(root) }

        let descriptor = drcDescriptor()
        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-1",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(
                        stageID: "001-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement()
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [descriptor]),
            healthResults: [
                descriptor.toolID: ToolHealthCheckResult(
                    toolID: descriptor.toolID,
                    status: .passed,
                    evidence: [qualifiedCorpusEvidence()]
                ),
            ],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "other-drc", status: .succeeded),
            ]
        )

        #expect(result.status == .blocked)
        #expect(result.stages[0].diagnostics.contains { $0.code == "EXECUTOR_TOOL_MISMATCH" })
        #expect(fileExists(".xcircuite/runs/run-1/stages/001-drc/result.json", in: root))
    }

    @Test func toolSelectionPrefersExecutorToolAmongEligibleCandidates() async throws {
        let root = try makeTemporaryRoot("tool-selection-prefers-executor")
        defer { removeTemporaryRoot(root) }

        // Two registered tools are eligible for the same operation; the
        // alphabetically-first one is NOT the stage executor's tool. The
        // orchestrator must select the executor's own tool instead of
        // blocking the stage with EXECUTOR_TOOL_MISMATCH.
        let competing = drcDescriptor()
        var executorOwned = drcDescriptor()
        executorOwned.toolID = "zeta-drc"
        executorOwned.displayName = "Zeta DRC"

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-1",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(
                        stageID: "001-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement()
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [competing, executorOwned]),
            healthResults: [
                competing.toolID: ToolHealthCheckResult(
                    toolID: competing.toolID,
                    status: .passed,
                    evidence: [qualifiedCorpusEvidence()]
                ),
                executorOwned.toolID: ToolHealthCheckResult(
                    toolID: executorOwned.toolID,
                    status: .passed,
                    evidence: [qualifiedCorpusEvidence("corpus-2")]
                ),
            ],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: executorOwned.toolID, status: .succeeded),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(result.stages[0].status == .succeeded)
        #expect(!result.stages[0].diagnostics.contains { $0.code == "EXECUTOR_TOOL_MISMATCH" })
        let toolchain = try await readToolchainManifest(in: root, runID: "run-1")
        #expect(toolchain.stages.first { $0.stageID == "001-drc" }?.selectedToolID == executorOwned.toolID)
    }

    @Test func executorFailurePersistsFailedStageAndRunManifest() async throws {
        let root = try makeTemporaryRoot("executor-failure")
        defer { removeTemporaryRoot(root) }

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-1",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(stageID: "001-drc", displayName: "DRC"),
                    FlowStageDefinition(stageID: "002-lvs", displayName: "LVS"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                ThrowingStageExecutor(stageID: "001-drc", toolID: "drc-tool"),
                StubStageExecutor(stageID: "002-lvs", toolID: "lvs-tool", status: .succeeded),
            ]
        )

        #expect(result.status == .failed)
        #expect(result.stages.count == 1)
        #expect(result.stages[0].status == .failed)
        #expect(result.stages[0].diagnostics.contains { $0.code == "STAGE_EXECUTOR_FAILED" })
        #expect(fileExists(".xcircuite/runs/run-1/stages/001-drc/result.json", in: root))
        #expect(!fileExists(".xcircuite/runs/run-1/stages/002-lvs/result.json", in: root))

        let runManifest = try await TestFlowInfrastructure.bound(to: root).readJSON(
            FlowRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(runManifest.status == .failed)
    }

    @Test func retryPolicyRetriesRetryableFailedStageAndPersistsAttempts() async throws {
        let root = try makeTemporaryRoot("retry-success")
        defer { removeTemporaryRoot(root) }

        let script = StageResultScript(results: [
            FlowStageResult(
                stageID: "001-drc",
                status: .failed,
                diagnostics: [
                    FlowDiagnostic(
                        severity: .error,
                        code: "TRANSIENT_TOOL_FAILURE",
                        message: "Temporary tool failure."
                    ),
                ]
            ),
            FlowStageResult(stageID: "001-drc", status: .succeeded),
        ])

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-retry-success",
                intent: "Retry transient DRC failure",
                stages: [
                    FlowStageDefinition(
                        stageID: "001-drc",
                        displayName: "DRC",
                        retryPolicy: FlowStageRetryPolicy(
                            maxAttempts: 2,
                            retryableDiagnosticCodes: ["TRANSIENT_TOOL_FAILURE"]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                ScriptedStageExecutor(stageID: "001-drc", toolID: "drc-tool", script: script),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(await script.executionCount() == 2)
        let stage = try #require(result.stages.first)
        #expect(stage.attempts.count == 2)
        #expect(stage.attempts[0].retryDecision.shouldRetry)
        #expect(stage.attempts[0].retryDecision.reason == .retryableDiagnosticMatched)
        #expect(stage.attempts[1].retryDecision.shouldRetry == false)
        #expect(stage.attempts[1].retryDecision.reason == .stageDidNotFail)

        let attempts = try await TestFlowInfrastructure.bound(to: root).readJSON(
            [FlowStageAttemptRecord].self,
            from: root.appending(path: ".xcircuite/runs/run-retry-success/stages/001-drc/attempts.json")
        )
        #expect(attempts.map(\.attemptIndex) == [1, 2])

        let ledger = try await TestFlowInfrastructure.bound(to: root).loadRunLedger(runID: "run-retry-success")
        #expect(ledger.progressEvents.map(\.kind).contains(.stageRetryScheduled))
        let summary = DefaultFlowRunLedgerSummarizer().summarize(ledger)
        #expect(summary.stages.first?.attemptCount == 2)
        #expect(summary.stages.first?.retryCount == 1)
        #expect(summary.nextActions.contains { $0.kind == "reviewRetryAttempts" })

        let manifest = try await TestFlowInfrastructure.bound(to: root).readJSON(
            FlowRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-retry-success/manifest.json")
        )
        #expect(manifest.artifacts.contains {
            $0.artifactID == "001-drc-attempts"
                && $0.path == ".xcircuite/runs/run-retry-success/stages/001-drc/attempts.json"
        })

        let bundle = try await makeTestReviewBundler(projectRoot: root).makeReviewBundle(
            runID: "run-retry-success",
            projectRoot: root
        )
        #expect(bundle.artifacts.contains { $0.purpose == .stageAttempts })
    }

    @Test func retryPolicyDoesNotRetryNonRetryableFailure() async throws {
        let root = try makeTemporaryRoot("retry-nonretryable")
        defer { removeTemporaryRoot(root) }

        let script = StageResultScript(results: [
            FlowStageResult(
                stageID: "001-drc",
                status: .failed,
                diagnostics: [
                    FlowDiagnostic(
                        severity: .error,
                        code: "PERMANENT_RULE_ERROR",
                        message: "The rule deck is invalid."
                    ),
                ]
            ),
        ])

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-retry-nonretryable",
                intent: "Do not retry permanent DRC failure",
                stages: [
                    FlowStageDefinition(
                        stageID: "001-drc",
                        displayName: "DRC",
                        retryPolicy: FlowStageRetryPolicy(
                            maxAttempts: 3,
                            retryableDiagnosticCodes: ["TRANSIENT_TOOL_FAILURE"]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                ScriptedStageExecutor(stageID: "001-drc", toolID: "drc-tool", script: script),
            ]
        )

        #expect(result.status == .failed)
        #expect(await script.executionCount() == 1)
        let stage = try #require(result.stages.first)
        #expect(stage.attempts.count == 1)
        #expect(stage.attempts[0].retryDecision.shouldRetry == false)
        #expect(stage.attempts[0].retryDecision.reason == .notRetryable)

        let ledger = try await TestFlowInfrastructure.bound(to: root).loadRunLedger(runID: "run-retry-nonretryable")
        #expect(!ledger.progressEvents.map(\.kind).contains(.stageRetryScheduled))
    }

    @Test func retryPolicyDoesNotRetryCancellation() async throws {
        let root = try makeTemporaryRoot("retry-cancellation")
        defer { removeTemporaryRoot(root) }

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-retry-cancellation",
                intent: "Do not retry cancelled DRC",
                stages: [
                    FlowStageDefinition(
                        stageID: "001-drc",
                        displayName: "DRC",
                        retryPolicy: FlowStageRetryPolicy(
                            maxAttempts: 3,
                            retryableDiagnosticCodes: [
                                "RUN_CANCELLATION_REQUESTED",
                                "STAGE_EXECUTOR_FAILED",
                            ]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                CooperativeCancellationStageExecutor(stageID: "001-drc", toolID: "drc-tool"),
            ]
        )

        #expect(result.status == .cancelled)
        let stage = try #require(result.stages.first)
        #expect(stage.attempts.count == 1)
        #expect(stage.attempts[0].retryDecision.shouldRetry == false)
        #expect(stage.attempts[0].retryDecision.reason == .cancellationObserved)

        let ledger = try await TestFlowInfrastructure.bound(to: root).loadRunLedger(runID: "run-retry-cancellation")
        #expect(!ledger.progressEvents.map(\.kind).contains(.stageRetryScheduled))
    }

    @Test func invalidRetryPolicyThrowsBeforeWritingRunArtifacts() async throws {
        let root = try makeTemporaryRoot("invalid-retry-policy")
        defer { removeTemporaryRoot(root) }

        await #expect(throws: FlowExecutionError.self) {
            try await makeTestOrchestrator(projectRoot: root).run(
                request: FlowOperationRequest(
                    projectRoot: root,
                    runID: "run-invalid-retry-policy",
                    intent: "Reject invalid retry policy",
                    stages: [
                        FlowStageDefinition(
                            stageID: "001-drc",
                            displayName: "DRC",
                            retryPolicy: FlowStageRetryPolicy(
                                maxAttempts: 0,
                                retryableDiagnosticCodes: ["TRANSIENT_TOOL_FAILURE"]
                            )
                        ),
                    ]
                ),
                toolRegistry: ToolRegistry(),
                healthResults: [:],
                executors: [
                    StubStageExecutor(stageID: "001-drc", toolID: "drc-tool", status: .succeeded),
                ]
            )
        }
        #expect(!fileExists(".xcircuite/runs/run-invalid-retry-policy", in: root, isDirectory: true))
    }

    @Test func missingExecutorThrowsBeforeWritingRunArtifacts() async throws {
        let root = try makeTemporaryRoot("missing-executor")
        defer { removeTemporaryRoot(root) }

        await #expect(throws: FlowExecutionError.self) {
            try await makeTestOrchestrator(projectRoot: root).run(
                request: FlowOperationRequest(
                    projectRoot: root,
                    runID: "run-1",
                    intent: "Run DRC and LVS",
                    stages: [
                        FlowStageDefinition(stageID: "001-drc", displayName: "DRC"),
                        FlowStageDefinition(stageID: "002-lvs", displayName: "LVS"),
                    ]
                ),
                toolRegistry: ToolRegistry(),
                healthResults: [:],
                executors: [
                    StubStageExecutor(stageID: "001-drc", toolID: "drc-tool", status: .succeeded),
                ]
            )
        }
        #expect(!fileExists(".xcircuite/runs/run-1", in: root, isDirectory: true))
    }

    @Test func duplicateStageIDsThrowTypedErrorBeforeWritingRunArtifacts() async throws {
        let root = try makeTemporaryRoot("duplicate-stage")
        defer { removeTemporaryRoot(root) }

        let request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-1",
            intent: "Run DRC",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC"),
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC duplicate"),
            ]
        )

        await #expect(throws: FlowExecutionError.self) {
            try await makeTestOrchestrator(projectRoot: root).run(
                request: request,
                toolRegistry: ToolRegistry(),
                healthResults: [:],
                executors: [
                    StubStageExecutor(stageID: "001-drc", toolID: "drc-tool", status: .succeeded),
                ]
            )
        }
        #expect(!fileExists(".xcircuite/runs/run-1", in: root, isDirectory: true))
    }

    @Test func pathUnsafeRunIDThrowsBeforeWritingRunArtifacts() async throws {
        let root = try makeTemporaryRoot("unsafe-run-id")
        defer { removeTemporaryRoot(root) }

        await #expect(throws: FlowIdentifierValidationError.self) {
            try await makeTestOrchestrator(projectRoot: root).run(
                request: FlowOperationRequest(
                    projectRoot: root,
                    runID: "../escape",
                    intent: "Run DRC",
                    stages: [
                        FlowStageDefinition(stageID: "001-drc", displayName: "DRC"),
                    ]
                ),
                toolRegistry: ToolRegistry(),
                healthResults: [:],
                executors: [
                    StubStageExecutor(stageID: "001-drc", toolID: "drc-tool", status: .succeeded),
                ]
            )
        }
        #expect(!fileExists("escape", in: root))
    }

    private func drcRequirement(
        requiredEvidenceKinds: [ToolEvidenceKind] = [],
        requiredQualifiedEvidenceKinds: [ToolEvidenceKind] = [],
        maximumEvidenceAgeSeconds: TimeInterval? = nil
    ) -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .smokeChecked,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json],
            requiredEvidenceKinds: requiredEvidenceKinds,
            requiredQualifiedEvidenceKinds: requiredQualifiedEvidenceKinds,
            maximumEvidenceAgeSeconds: maximumEvidenceAgeSeconds
        )
    }

    private func drcDescriptor() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-drc",
            displayName: "Native DRC",
            kind: .drc,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-drc",
                    inputFormats: [.oasis],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(level: .smokeChecked),
            environment: ToolEnvironment(platform: "macOS")
        )
    }

    private func qualifiedCorpusEvidence(_ evidenceID: String = "corpus-1") -> ToolEvidence {
        ToolEvidence(
            evidenceID: evidenceID,
            kind: .corpus
        )
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "DefaultFlowOrchestratorTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }

    private func fileExists(_ relativePath: String, in root: URL, isDirectory expectedDirectory: Bool? = nil) -> Bool {
        var isDirectory: ObjCBool = false
        let path = root.appending(path: relativePath).path(percentEncoded: false)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        if let expectedDirectory {
            return exists && isDirectory.boolValue == expectedDirectory
        }
        return exists
    }

    private func copyProgressStressArtifactIfRequested(root: URL, runID: String) throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LSI_PROGRESS_STRESS_ARTIFACT_OUT"],
              !outputPath.isEmpty else {
            return
        }
        let source = root.appending(path: ".xcircuite/runs/\(runID)/progress.jsonl")
        let destination = URL(filePath: outputPath)
        let destinationPath = destination.path(percentEncoded: false)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destinationPath) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func readToolchainManifest(in root: URL, runID: String) async throws -> FlowToolchainManifest {
        try await TestFlowInfrastructure.bound(to: root).readJSON(
            FlowToolchainManifest.self,
            from: root.appending(path: ".xcircuite/runs/\(runID)/toolchain.json")
        )
    }

    private func assertToolchainArtifact(in root: URL, runID: String) async throws -> ArtifactReference {
        let runManifest = try await TestFlowInfrastructure.bound(to: root).readJSON(
            FlowRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/\(runID)/manifest.json")
        )
        let path = ".xcircuite/runs/\(runID)/toolchain.json"
        let reference = try #require(runManifest.artifacts.first { $0.path == path })
        #expect(reference.kind == .other)
        #expect(reference.format == .json)
        let sha256 = reference.sha256
        #expect(!sha256.isEmpty)
        #expect(reference.producer?.identifier == runID)
        return reference
    }
}

private struct StubStageExecutor: FlowStageExecutor {
    let stageID: String
    let toolID: String
    let status: FlowStageStatus

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        FlowStageResult(stageID: stage.stageID, status: status)
    }
}

private struct ThrowingStageExecutor: FlowStageExecutor {
    let stageID: String
    let toolID: String

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        throw StubStageError.executionFailed
    }
}

private actor StageResultScript {
    private var results: [FlowStageResult]
    private var count: Int = 0

    init(results: [FlowStageResult]) {
        self.results = results
    }

    func nextResult() throws -> FlowStageResult {
        count += 1
        guard !results.isEmpty else {
            throw StubStageError.executionFailed
        }
        return results.removeFirst()
    }

    func executionCount() -> Int {
        count
    }
}

private actor ProgressLineSink {
    private var state: [FlowRunProgressEvent] = []

    func append(_ event: FlowRunProgressEvent) {
        state.append(event)
    }

    func events() -> [FlowRunProgressEvent] {
        state
    }
}

private struct ScriptedStageExecutor: FlowStageExecutor {
    let stageID: String
    let toolID: String
    let script: StageResultScript

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        try await script.nextResult()
    }
}

private struct DelayedScriptedStageExecutor: FlowStageExecutor {
    let stageID: String
    let toolID: String
    let script: StageResultScript
    let delayNanoseconds: UInt64

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return try await script.nextResult()
    }
}

private struct CooperativeCancellationStageExecutor: FlowStageExecutor {
    let stageID: String
    let toolID: String

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        _ = try await makeTestCancellationRecorder(projectRoot: context.projectRoot).requestCancellation(
            projectRoot: context.projectRoot,
            runID: context.runID,
            requestedBy: toolID,
            reason: "cooperative cancellation checkpoint"
        )
        try await context.checkCancellation()
        return FlowStageResult(stageID: stage.stageID, status: .succeeded)
    }
}

private enum StubStageError: Error {
    case executionFailed
}

// MARK: - Approval gate (P4)

@Suite("Approval gate")
struct ApprovalGateTests {
    @Test func approvalAbsentBlocksTheRunUntilDecided() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "dfk-approval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeTemporaryItem(root) }

        var request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-approve",
            intent: "Approval flow",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
                FlowStageDefinition(stageID: "002-ship", displayName: "Ship"),
            ]
        )
        let executors: [any FlowStageExecutor] = [
            StubStageExecutor(stageID: "001-drc", toolID: "drc-tool", status: .succeeded),
            StubStageExecutor(stageID: "002-ship", toolID: "ship-tool", status: .succeeded),
        ]

        // 1. No decision recorded: the run blocks at the gate; the
        //    second stage never runs.
        let blocked = try await makeTestOrchestrator(projectRoot: root).run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(blocked.status == .blocked)
        #expect(blocked.stages.count == 1)
        #expect(blocked.stages[0].gates.contains {
            $0.gateID == "approval" && $0.status == .incomplete
        })

        // 2. The cockpit records the decision; re-running the same runID
        //    resumes past the gate.
        _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
            FlowGateApprovalRequest(
                projectRoot: root,
                runID: "run-approve",
                stageID: "001-drc",
                verdict: .approved,
                reviewer: "reviewer-1",
                note: "looks clean"
            )
        )
        request.allowExistingRunDirectory = true
        let resumed = try await makeTestOrchestrator(projectRoot: root).run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(resumed.status == .succeeded)
        #expect(resumed.stages.count == 2)
        #expect(resumed.stages[0].gates.contains {
            $0.gateID == "approval" && $0.status == .passed
        })
    }

    @Test func rejectionFailsTheStage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "dfk-reject-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeTemporaryItem(root) }

        var request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-reject",
            intent: "Approval flow",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
            ]
        )
        let initial = try await makeTestOrchestrator(projectRoot: root).run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "drc-tool", status: .succeeded),
            ]
        )
        #expect(initial.status == .blocked)
        _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
            FlowGateApprovalRequest(
                projectRoot: root,
                runID: "run-reject",
                stageID: "001-drc",
                verdict: .rejected,
                reviewer: "reviewer-1",
                note: "needs a wider rail"
            )
        )

        request.allowExistingRunDirectory = true

        let result = try await makeTestOrchestrator(projectRoot: root).run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "drc-tool", status: .succeeded),
            ]
        )
        #expect(result.status == .failed)
        #expect(result.stages[0].gates.contains {
            $0.gateID == "approval" && $0.status == .failed
        })
        #expect(result.stages[0].diagnostics.contains { $0.code == "STAGE_REJECTED" })
    }

    private func removeTemporaryItem(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove temporary item: \(error)")
        }
    }
}

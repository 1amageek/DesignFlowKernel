import DesignFlowKernel
import CircuiteFoundation
import Foundation
import Testing

@Suite("Flow run loop guard", .timeLimit(.minutes(1)))
struct FlowRunLoopGuardTests {
    @Test func guardReportsMissingRequiredEvidence() async throws {
        let root = try makeTemporaryRoot("missing-evidence")
        defer { removeTemporaryRoot(root) }
        let runID = "run-missing-evidence"
        let store = await TestFlowInfrastructure.bound(to: root)
        try await store.createWorkspace(at: root)
        _ = try await store.ensureRunDirectory(for: runID, inProjectAt: root)
        try await store.appendRunAction(
            FlowRunActionRecord(
                actionID: "action-1",
                runID: runID,
                actor: FlowRunActor(kind: .agent, identifier: "external-agent"),
                actionKind: "layout.edit",
                status: .succeeded,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            inProjectAt: root
        )

        let profile = FlowAgentLoopProfile(
            profileID: "opamp-loop-profile",
            budgets: FlowAgentLoopProfile.Budgets(maxActions: 10),
            requiredEvidence: [
                FlowAgentLoopProfile.RequiredEvidence(
                    evidenceID: "required-simulation",
                    artifactRole: "simulation-summary"
                ),
            ]
        )
        let result = try await makeGuardEvaluator(store: store).evaluateRunGuard(
            runID: runID,
            workspaceID: try testWorkspaceID(for: root),
            profile: profile,
            generatedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(result.verdict.status == .needsHumanReview)
        #expect(result.verdict.triggeredDetectors.contains { $0.detectorID == "missingRequiredEvidence" })
        #expect(fileExists(".xcircuite/runs/\(runID)/loop/snapshot.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/loop/guard-verdict.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/loop/iterations.jsonl", in: root))
    }

    @Test func guardContinuesWhenRequiredEvidenceIsPresent() async throws {
        let root = try makeTemporaryRoot("present-evidence")
        defer { removeTemporaryRoot(root) }
        let runID = "run-present-evidence"
        let store = await TestFlowInfrastructure.bound(to: root)
        try await store.createWorkspace(at: root)
        _ = try await store.ensureRunDirectory(for: runID, inProjectAt: root)
        try await store.appendRunAction(
            FlowRunActionRecord(
                actionID: "action-1",
                runID: runID,
                actor: FlowRunActor(kind: .agent, identifier: "external-agent"),
                actionKind: "simulation.run",
                status: .succeeded,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            inProjectAt: root
        )
        try await writeSimulationSummaryEnvelope(root: root, runID: runID)

        let profile = FlowAgentLoopProfile(
            profileID: "opamp-loop-profile",
            requiredEvidence: [
                FlowAgentLoopProfile.RequiredEvidence(
                    evidenceID: "required-simulation",
                    artifactRole: "simulation-summary"
                ),
            ]
        )
        let result = try await makeGuardEvaluator(store: store).evaluateRunGuard(
            runID: runID,
            workspaceID: try testWorkspaceID(for: root),
            profile: profile,
            generatedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(result.verdict.status == .continue)
        #expect(result.snapshot.evidenceCoverage.missingCount == 0)
        #expect(result.snapshot.metricTrend.acceptedCount > 0)
    }

    @Test func crossArtifactEvaluationPersistsAndFeedsReviewBundle() async throws {
        let root = try makeTemporaryRoot("cross-artifact-review")
        defer { removeTemporaryRoot(root) }
        let runID = "run-cross-artifact-review"
        let store = await TestFlowInfrastructure.bound(to: root)
        try await store.createWorkspace(at: root)
        _ = try await store.ensureRunDirectory(for: runID, inProjectAt: root)
        try await store.appendRunAction(
            FlowRunActionRecord(
                actionID: "action-1",
                runID: runID,
                actor: FlowRunActor(kind: .agent, identifier: "external-agent"),
                actionKind: "simulation.run",
                status: .succeeded,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            inProjectAt: root
        )
        try await writeSimulationSummaryEnvelope(root: root, runID: runID)
        try await writeRejectedDRCSummaryEnvelope(root: root, runID: runID)

        let loopProfile = FlowAgentLoopProfile(
            profileID: "loop-profile",
            requiredEvidence: [
                FlowAgentLoopProfile.RequiredEvidence(
                    evidenceID: "required-simulation",
                    artifactRole: "simulation-summary"
                ),
            ]
        )
        _ = try await makeGuardEvaluator(store: store).evaluateRunGuard(
            runID: runID,
            workspaceID: try testWorkspaceID(for: root),
            profile: loopProfile,
            generatedAt: Date(timeIntervalSince1970: 200)
        )

        let evaluationProfile = FlowEvaluationProfile(
            profileID: "evaluation-profile",
            domain: "analog",
            metricChannels: [
                FlowEvaluationProfile.MetricChannel(
                    channelID: "gain",
                    direction: .maximize
                ),
                FlowEvaluationProfile.MetricChannel(
                    channelID: "drc.violationCount",
                    direction: .minimize
                ),
            ],
            requiredAnalyses: [
                FlowEvaluationProfile.RequiredAnalysis(
                    analysisID: "simulation",
                    domain: "simulation",
                    artifactRole: "simulation-summary"
                ),
                FlowEvaluationProfile.RequiredAnalysis(
                    analysisID: "drc",
                    domain: "layout",
                    artifactRole: "drc-summary"
                ),
            ],
            artifactRoles: [
                FlowEvaluationProfile.ArtifactRole(role: "simulation-summary"),
                FlowEvaluationProfile.ArtifactRole(role: "drc-summary"),
            ]
        )
        let evaluationResult = try await DefaultFlowRunCrossArtifactEvaluator(
            loader: store,
            evidencePersistence: store
        ).compareArtifacts(
            runID: runID,
            workspaceID: try testWorkspaceID(for: root),
            profile: evaluationProfile
        )
        let bundle = try await DefaultFlowRunReviewBundler(
            loader: store,
            persistence: store
        ).makeReviewBundle(
            runID: runID,
            workspaceID: try testWorkspaceID(for: root)
        )

        #expect(evaluationResult.evaluation.status == .rejected)
        let evaluationArtifact = try #require(evaluationResult.artifactReferences.first)
        #expect(evaluationArtifact.id.rawValue == "cross-artifact-evaluation")
        #expect(evaluationArtifact.locator.role == .output)
        #expect(evaluationArtifact.locator.kind == .report)
        #expect(evaluationArtifact.locator.format == .json)
        #expect(evaluationArtifact.byteCount > 0)
        #expect(fileExists(".xcircuite/runs/\(runID)/reports/cross-artifact-evaluation.json", in: root))
        #expect(bundle.runGuardVerdict != nil)
        #expect(bundle.crossArtifactEvaluation?.status == .rejected)
        #expect(bundle.reviewItems.contains { $0.kind == .crossArtifactEvaluation && $0.status == .needsRepair })
        #expect(bundle.artifacts.contains { $0.reference.artifactID == "cross-artifact-evaluation" })
    }

    private func makeGuardEvaluator(
        store: TestFlowInfrastructure
    ) -> DefaultFlowRunGuardEvaluator {
        DefaultFlowRunGuardEvaluator(
            snapshotBuilder: DefaultFlowRunLoopSnapshotBuilder(
                loader: store,
                evidencePersistence: store
            ),
            persistence: store
        )
    }

    private func writeSimulationSummaryEnvelope(root: URL, runID: String) async throws {
        let store = await TestFlowInfrastructure.bound(to: root)
        let summaryPath = ".xcircuite/runs/\(runID)/evidence/simulation-summary.json"
        let summaryURL = root.appending(path: summaryPath)
        try FileManager.default.createDirectory(
            at: summaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"status":"accepted"}"#.utf8).write(to: summaryURL, options: .atomic)
        let reference = try foundationReference(
            path: summaryPath,
            artifactID: "simulation-summary",
            projectRoot: root
        )
        let envelope = FlowArtifactEnvelope(
            artifactID: "simulation-summary",
            role: "simulation-summary",
            reference: reference,
            evaluationResult: FlowEvaluationResult(
                evaluationID: "simulation-evaluation",
                specID: "opamp-spec",
                status: .accepted,
                channelResults: [
                    FlowEvaluationChannelResult(
                        channelID: "gain",
                        status: .accepted,
                        observedValue: FlowMetricValue.scalar(60)
                    ),
                ],
                summary: "Simulation summary accepted."
            )
        )
        try await store.writeArtifactEnvelope(envelope, runID: runID, inProjectAt: root)
    }

    private func writeRejectedDRCSummaryEnvelope(root: URL, runID: String) async throws {
        let store = await TestFlowInfrastructure.bound(to: root)
        let summaryPath = ".xcircuite/runs/\(runID)/evidence/drc-summary.json"
        let summaryURL = root.appending(path: summaryPath)
        try FileManager.default.createDirectory(
            at: summaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"violationCount":2}"#.utf8).write(to: summaryURL, options: .atomic)
        let reference = try foundationReference(
            path: summaryPath,
            artifactID: "drc-summary",
            projectRoot: root
        )
        let envelope = FlowArtifactEnvelope(
            artifactID: "drc-summary",
            role: "drc-summary",
            reference: reference,
            observationSet: FlowObservationSet(
                observationSetID: "drc-observations",
                channels: [
                    FlowObservationChannel(
                        channelID: "drc.violationCount",
                        status: .observed,
                    value: FlowMetricValue.scalar(2)
                    ),
                ]
            ),
            evaluationResult: FlowEvaluationResult(
                evaluationID: "drc-evaluation",
                specID: "opamp-spec",
                status: .rejected,
                channelResults: [
                    FlowEvaluationChannelResult(
                        channelID: "drc.violationCount",
                        status: .rejected,
                        observedValue: FlowMetricValue.scalar(2)
                    ),
                ],
                summary: "DRC violations remain."
            )
        )
        try await store.writeArtifactEnvelope(envelope, runID: runID, inProjectAt: root)
    }

    private func foundationReference(
        path: String,
        artifactID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .output,
            kind: .report,
            format: .json
        )
        let reference = try LocalArtifactReferencer().reference(
            locator,
            relativeTo: projectRoot
        )
        return ArtifactReference(
            id: try ArtifactID(rawValue: artifactID),
            locator: reference.locator,
            digest: reference.digest,
            byteCount: reference.byteCount,
            producer: reference.producer
        )
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "FlowRunLoopGuardTests-\(name)-\(UUID().uuidString)")
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

    private func fileExists(_ relativePath: String, in root: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: root.appending(path: relativePath).path(percentEncoded: false),
            isDirectory: &isDirectory
        ) && !isDirectory.boolValue
    }
}

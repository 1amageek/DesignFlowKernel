import DesignFlowCLISupport
import DesignFlowKernel
import Foundation
import Testing
import DesignFlowKernel

@Suite("Flow run loop guard", .timeLimit(.minutes(1)))
struct FlowRunLoopGuardTests {
    @Test func guardReportsMissingRequiredEvidence() throws {
        let root = try makeTemporaryRoot("missing-evidence")
        defer { removeTemporaryRoot(root) }
        let runID = "run-missing-evidence"
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.ensureRunDirectory(for: runID, inProjectAt: root)
        try store.appendRunAction(
            XcircuiteRunActionRecord(
                actionID: "action-1",
                runID: runID,
                actor: XcircuiteRunActionActor(kind: .agent, identifier: "external-agent"),
                actionKind: "layout.edit",
                status: .succeeded,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            inProjectAt: root
        )

        let profile = XcircuiteAgentLoopProfile(
            profileID: "opamp-loop-profile",
            budgets: XcircuiteAgentLoopProfile.Budgets(maxActions: 10),
            requiredEvidence: [
                XcircuiteAgentLoopProfile.RequiredEvidence(
                    evidenceID: "required-simulation",
                    artifactRole: "simulation-summary"
                ),
            ]
        )
        let result = try DefaultFlowRunGuardEvaluator().evaluateRunGuard(
            runID: runID,
            projectRoot: root,
            profile: profile,
            generatedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(result.verdict.status == .needsHumanReview)
        #expect(result.verdict.triggeredDetectors.contains { $0.detectorID == "missingRequiredEvidence" })
        #expect(fileExists(".xcircuite/runs/\(runID)/loop/snapshot.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/loop/guard-verdict.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/loop/iterations.jsonl", in: root))
    }

    @Test func guardContinuesWhenRequiredEvidenceIsPresent() throws {
        let root = try makeTemporaryRoot("present-evidence")
        defer { removeTemporaryRoot(root) }
        let runID = "run-present-evidence"
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.ensureRunDirectory(for: runID, inProjectAt: root)
        try store.appendRunAction(
            XcircuiteRunActionRecord(
                actionID: "action-1",
                runID: runID,
                actor: XcircuiteRunActionActor(kind: .agent, identifier: "external-agent"),
                actionKind: "simulation.run",
                status: .succeeded,
                outputs: [
                    XcircuiteFileReference(
                        artifactID: "simulation-summary",
                        path: ".xcircuite/runs/\(runID)/evidence/simulation-summary.json",
                        kind: .report,
                        format: .json
                    ),
                ],
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            inProjectAt: root
        )
        try writeSimulationSummaryEnvelope(root: root, runID: runID)

        let profile = XcircuiteAgentLoopProfile(
            profileID: "opamp-loop-profile",
            requiredEvidence: [
                XcircuiteAgentLoopProfile.RequiredEvidence(
                    evidenceID: "required-simulation",
                    artifactRole: "simulation-summary"
                ),
            ]
        )
        let result = try DefaultFlowRunGuardEvaluator().evaluateRunGuard(
            runID: runID,
            projectRoot: root,
            profile: profile,
            generatedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(result.verdict.status == .continue)
        #expect(result.snapshot.evidenceCoverage.missingCount == 0)
        #expect(result.snapshot.metricTrend.acceptedCount > 0)
    }

    @Test func cliEvaluatesRunGuardAndPersistsArtifacts() throws {
        let root = try makeTemporaryRoot("cli")
        defer { removeTemporaryRoot(root) }
        let runID = "run-cli-guard"
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.ensureRunDirectory(for: runID, inProjectAt: root)
        try store.appendRunAction(
            XcircuiteRunActionRecord(
                actionID: "action-1",
                runID: runID,
                actor: XcircuiteRunActionActor(kind: .agent, identifier: "external-agent"),
                actionKind: "simulation.run",
                status: .succeeded,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            inProjectAt: root
        )

        let profile = XcircuiteAgentLoopProfile(
            profileID: "cli-loop-profile",
            budgets: XcircuiteAgentLoopProfile.Budgets(maxActions: 0)
        )
        let profileURL = root.appending(path: "agent-loop-profile.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: profileURL, options: .atomic)

        let output = try DesignFlowCLICommand.run(arguments: [
            "evaluate-run-guard",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--profile",
            profileURL.path(percentEncoded: false),
            "--pretty",
        ])
        let data = try #require(output.data(using: .utf8))
        let result = try JSONDecoder().decode(FlowRunGuardEvaluationResult.self, from: data)

        #expect(result.verdict.status == .needsHumanReview)
        #expect(result.verdict.triggeredDetectors.contains { $0.detectorID == "budgetExceeded" })
        #expect(fileExists(".xcircuite/runs/\(runID)/loop/guard-verdict.json", in: root))
    }

    @Test func crossArtifactEvaluationPersistsAndFeedsReviewBundle() throws {
        let root = try makeTemporaryRoot("cross-artifact-review")
        defer { removeTemporaryRoot(root) }
        let runID = "run-cross-artifact-review"
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.ensureRunDirectory(for: runID, inProjectAt: root)
        try store.appendRunAction(
            XcircuiteRunActionRecord(
                actionID: "action-1",
                runID: runID,
                actor: XcircuiteRunActionActor(kind: .agent, identifier: "external-agent"),
                actionKind: "simulation.run",
                status: .succeeded,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            inProjectAt: root
        )
        try writeSimulationSummaryEnvelope(root: root, runID: runID)
        try writeRejectedDRCSummaryEnvelope(root: root, runID: runID)

        let loopProfile = XcircuiteAgentLoopProfile(
            profileID: "loop-profile",
            requiredEvidence: [
                XcircuiteAgentLoopProfile.RequiredEvidence(
                    evidenceID: "required-simulation",
                    artifactRole: "simulation-summary"
                ),
            ]
        )
        _ = try DefaultFlowRunGuardEvaluator().evaluateRunGuard(
            runID: runID,
            projectRoot: root,
            profile: loopProfile,
            generatedAt: Date(timeIntervalSince1970: 200)
        )

        let evaluationProfile = XcircuiteEvaluationProfile(
            profileID: "evaluation-profile",
            domain: "analog",
            metricChannels: [
                XcircuiteEvaluationProfile.MetricChannel(
                    channelID: "gain",
                    direction: .maximize
                ),
                XcircuiteEvaluationProfile.MetricChannel(
                    channelID: "drc.violationCount",
                    direction: .minimize
                ),
            ],
            requiredAnalyses: [
                XcircuiteEvaluationProfile.RequiredAnalysis(
                    analysisID: "simulation",
                    domain: "simulation",
                    artifactRole: "simulation-summary"
                ),
                XcircuiteEvaluationProfile.RequiredAnalysis(
                    analysisID: "drc",
                    domain: "layout",
                    artifactRole: "drc-summary"
                ),
            ],
            artifactRoles: [
                XcircuiteEvaluationProfile.ArtifactRole(role: "simulation-summary"),
                XcircuiteEvaluationProfile.ArtifactRole(role: "drc-summary"),
            ]
        )
        let evaluationProfileURL = root.appending(path: "evaluation-profile.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evaluationProfile).write(to: evaluationProfileURL, options: .atomic)
        let output = try DesignFlowCLICommand.run(arguments: [
            "compare-artifacts",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--profile",
            evaluationProfileURL.path(percentEncoded: false),
            "--pretty",
        ])
        let data = try #require(output.data(using: .utf8))
        let evaluationResult = try JSONDecoder().decode(
            FlowRunCrossArtifactEvaluationResult.self,
            from: data
        )
        let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
            runID: runID,
            projectRoot: root
        )

        #expect(evaluationResult.evaluation.status == .rejected)
        #expect(fileExists(".xcircuite/runs/\(runID)/reports/cross-artifact-evaluation.json", in: root))
        #expect(bundle.runGuardVerdict != nil)
        #expect(bundle.crossArtifactEvaluation?.status == .rejected)
        #expect(bundle.reviewItems.contains { $0.kind == .crossArtifactEvaluation && $0.status == .needsRepair })
        #expect(bundle.artifacts.contains { $0.artifactID == "cross-artifact-evaluation" })
    }

    private func writeSimulationSummaryEnvelope(root: URL, runID: String) throws {
        let store = XcircuitePackageStore()
        let summaryPath = ".xcircuite/runs/\(runID)/evidence/simulation-summary.json"
        let summaryURL = root.appending(path: summaryPath)
        try FileManager.default.createDirectory(
            at: summaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"status":"accepted"}"#.utf8).write(to: summaryURL, options: .atomic)
        let reference = try store.fileReference(
            forProjectRelativePath: summaryPath,
            artifactID: "simulation-summary",
            kind: .report,
            format: .json,
            inProjectAt: root,
            producedByRunID: runID
        )
        let envelope = XcircuiteArtifactEnvelope(
            artifactID: "simulation-summary",
            role: "simulation-summary",
            reference: reference,
            evaluationResult: XcircuiteEvaluationResult(
                evaluationID: "simulation-evaluation",
                specID: "opamp-spec",
                status: .accepted,
                channelResults: [
                    XcircuiteEvaluationChannelResult(
                        channelID: "gain",
                        status: .accepted,
                        observedValue: .number(60)
                    ),
                ],
                summary: "Simulation summary accepted."
            )
        )
        try store.writeArtifactEnvelope(envelope, runID: runID, inProjectAt: root)
    }

    private func writeRejectedDRCSummaryEnvelope(root: URL, runID: String) throws {
        let store = XcircuitePackageStore()
        let summaryPath = ".xcircuite/runs/\(runID)/evidence/drc-summary.json"
        let summaryURL = root.appending(path: summaryPath)
        try FileManager.default.createDirectory(
            at: summaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"violationCount":2}"#.utf8).write(to: summaryURL, options: .atomic)
        let reference = try store.fileReference(
            forProjectRelativePath: summaryPath,
            artifactID: "drc-summary",
            kind: .report,
            format: .json,
            inProjectAt: root,
            producedByRunID: runID
        )
        let envelope = XcircuiteArtifactEnvelope(
            artifactID: "drc-summary",
            role: "drc-summary",
            reference: reference,
            observationSet: XcircuiteObservationSet(
                observationSetID: "drc-observations",
                channels: [
                    XcircuiteObservationChannel(
                        channelID: "drc.violationCount",
                        status: .observed,
                        value: .number(2)
                    ),
                ]
            ),
            evaluationResult: XcircuiteEvaluationResult(
                evaluationID: "drc-evaluation",
                specID: "opamp-spec",
                status: .rejected,
                channelResults: [
                    XcircuiteEvaluationChannelResult(
                        channelID: "drc.violationCount",
                        status: .rejected,
                        observedValue: .number(2)
                    ),
                ],
                summary: "DRC violations remain."
            )
        )
        try store.writeArtifactEnvelope(envelope, runID: runID, inProjectAt: root)
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

import DesignFlowKernel
import DesignFlowCLISupport
import Foundation
import Testing
import ToolQualification
import XcircuitePackage

private struct StaticReviewBundler: FlowRunReviewBundling {
    var bundle: FlowRunReviewBundle

    func makeReviewBundle(runID: String, projectRoot: URL) throws -> FlowRunReviewBundle {
        bundle
    }
}

private func verifiedTestIntegrity() -> FlowRunReviewArtifactIntegrity {
    FlowRunReviewArtifactIntegrity(
        status: .verified,
        expectedSHA256: String(repeating: "a", count: 64),
        actualSHA256: String(repeating: "a", count: 64),
        expectedByteCount: 2,
        actualByteCount: 2,
        message: "Verified test artifact."
    )
}

extension FlowRunLedgerSummaryTests {
@Test func decisionPacketBuilderPersistsPacketAndRegistersRunArtifact() async throws {
    let root = try makeTemporaryRoot("agent-decision-packet")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let summaryPayload = Data(#"{"artifactID":"drc-summary"}"#.utf8)
    try await createBlockedApprovalRun(
        root: root,
        runID: "run-1",
        artifacts: [
            XcircuiteFileReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: summaryPayload]
    )

    let result = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    #expect(result.artifact.artifactID == "review-decision-packet")
    #expect(result.artifact.path == ".xcircuite/runs/run-1/review/decision-packet.json")
    #expect(result.packet.readiness == .needsReview)
    #expect(result.packet.requiredArtifacts.contains {
        $0.role == "stage-summary" && $0.status == .satisfied
    })
    #expect(result.packet.unresolvedReviewItems.contains {
        $0.kind == .approvalGate && $0.status == .needsReview
    })
    #expect(result.packet.replayCommands.contains {
        $0.commandID == "review-run" && $0.readiness == .ready
    })

    let storedPacket = try XcircuitePackageStore().readJSON(
        FlowRunDecisionPacket.self,
        from: root.appending(path: ".xcircuite/runs/run-1/review/decision-packet.json")
    )
    #expect(storedPacket.packetID == "decision-packet-run-1")

    let manifest = try XcircuitePackageStore().readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
    )
    #expect(manifest.artifacts.contains {
        $0.artifactID == "review-decision-packet"
            && $0.path == ".xcircuite/runs/run-1/review/decision-packet.json"
    })
}

@Test func buildDecisionPacketCLIEmitsPacketResultJSON() async throws {
    let root = try makeTemporaryRoot("agent-decision-packet-cli")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let summaryPayload = Data(#"{"artifactID":"drc-summary"}"#.utf8)
    try await createBlockedApprovalRun(
        root: root,
        runID: "run-1",
        artifacts: [
            XcircuiteFileReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: summaryPayload]
    )

    let json = try DesignFlowCLICommand.run(
        arguments: [
            "build-decision-packet",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(FlowRunDecisionPacketBuildResult.self, from: data)

    #expect(result.artifact.artifactID == "review-decision-packet")
    #expect(result.packet.runID == "run-1")
    #expect(result.packet.readiness == .needsReview)
    #expect(result.packet.completionIssues.contains {
        $0.code == "unresolved-review-item"
            && $0.reviewItemID == "001-drc-decide-approval"
    })
}

@Test func decisionPacketValidatorPersistsNeedsReviewValidationArtifact() async throws {
    let root = try makeTemporaryRoot("agent-decision-packet-validation")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let summaryPayload = Data(#"{"artifactID":"drc-summary"}"#.utf8)
    try await createBlockedApprovalRun(
        root: root,
        runID: "run-1",
        artifacts: [
            XcircuiteFileReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: summaryPayload]
    )
    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    let validation = try DefaultFlowRunDecisionPacketValidator().validateDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    #expect(validation.status == .needsReview)
    #expect(validation.packetReadiness == .needsReview)
    #expect(validation.packetArtifactIntegrity?.status == .verified)
    #expect(validation.requiredArtifactCount > 0)
    #expect(validation.unresolvedReviewItemCount == 1)
    #expect(validation.completionIssueCount == 1)
    #expect(validation.validationArtifactPath == ".xcircuite/runs/run-1/review/decision-packet-validation.json")
    #expect(validation.diagnostics.contains {
        $0.code == "decision-packet-unresolved-review-item"
    })

    let manifest = try XcircuitePackageStore().readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
    )
    #expect(manifest.artifacts.contains {
        $0.artifactID == "review-decision-packet-validation"
            && $0.path == ".xcircuite/runs/run-1/review/decision-packet-validation.json"
    })
}

@Test func decisionPacketValidatorBlocksStalePacketAfterApprovalChangesLedger() async throws {
    let root = try makeTemporaryRoot("agent-decision-packet-stale-after-approval")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    _ = try DefaultFlowGateApprovalRecorder().recordApproval(
        FlowGateApprovalRequest(
            projectRoot: root,
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )

    let validation = try DefaultFlowRunDecisionPacketValidator().validateDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    #expect(validation.status == .blocked)
    #expect(validation.packetArtifactIntegrity?.status == .verified)
    #expect(validation.diagnostics.contains {
        $0.code == "decision-packet-stale-approvals"
    })
    #expect(validation.diagnostics.contains {
        $0.code == "decision-packet-stale-review-items"
    })
}

@Test func validateDecisionPacketProcessExitIsNonZeroWhenValidationBlocks() async throws {
    let root = try makeTemporaryRoot("agent-decision-packet-process-exit")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let result = try await DesignFlowCLICommand.runProcess(
        arguments: [
            "validate-decision-packet",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
        ]
    )
    let data = try #require(result.output.data(using: .utf8))
    let validation = try JSONDecoder().decode(FlowRunDecisionPacketValidationResult.self, from: data)

    #expect(validation.status == .blocked)
    #expect(result.exitCode == 2)
}

	@Test func validateDecisionPacketCLIBlocksMissingPacketWithJSONDiagnostics() async throws {
	    let root = try makeTemporaryRoot("agent-decision-packet-validation-cli")
	    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let json = try DesignFlowCLICommand.run(
        arguments: [
            "validate-decision-packet",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let validation = try JSONDecoder().decode(FlowRunDecisionPacketValidationResult.self, from: data)

    #expect(validation.status == .blocked)
    #expect(validation.validationArtifactPath == ".xcircuite/runs/run-1/review/decision-packet-validation.json")
    #expect(validation.diagnostics.contains {
        $0.code == "decision-packet-artifact-reference-missing"
    })
	    #expect(validation.diagnostics.contains {
	        $0.code == "decision-packet-unreadable"
	    })
	}

	@Test func decisionPacketValidatorBlocksArtifactReferenceMismatch() async throws {
	    let root = try makeTemporaryRoot("agent-decision-packet-reference-mismatch")
	    defer { removeTemporaryRoot(root) }
	    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
	    try await createBlockedApprovalRun(
	        root: root,
	        runID: "run-1",
	        artifacts: [
	            XcircuiteFileReference(
	                artifactID: "drc-summary",
	                path: summaryPath,
	                kind: .report,
	                format: .json
	            ),
	        ],
	        artifactPayloads: [summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8)]
	    )
	    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
	        runID: "run-1",
	        projectRoot: root
	    )

	    let store = XcircuitePackageStore()
	    let manifest = try store.loadRunManifest(runID: "run-1", inProjectAt: root)
	    let packetPath = ".xcircuite/runs/run-1/review/decision-packet.json"
	    var mismatchedReference = try #require(manifest.artifacts.first {
	        $0.path == packetPath
	    })
	    mismatchedReference.artifactID = "wrong-decision-packet"
	    _ = try store.upsertRunArtifacts(
	        [mismatchedReference],
	        runID: "run-1",
	        inProjectAt: root
	    )

	    let validation = try DefaultFlowRunDecisionPacketValidator().validateDecisionPacket(
	        runID: "run-1",
	        projectRoot: root
	    )

	    #expect(validation.status == .blocked)
	    #expect(validation.packetArtifactIntegrity == nil)
	    #expect(validation.diagnostics.contains {
	        $0.code == "decision-packet-artifact-reference-mismatch"
	    })
	}

	@Test func validateDecisionPacketCLIBlocksUnreadableRunManifestWithJSONDiagnostics() async throws {
	    let root = try makeTemporaryRoot("agent-decision-packet-validation-missing-manifest")
    defer { removeTemporaryRoot(root) }
    let store = XcircuitePackageStore()
    try store.createPackage(at: root)
    let runDirectory = try XcircuitePackage(projectRoot: root).runDirectoryURL(for: "run-1")
    try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

    let json = try DesignFlowCLICommand.run(
        arguments: [
            "validate-decision-packet",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let validation = try JSONDecoder().decode(FlowRunDecisionPacketValidationResult.self, from: data)

    #expect(validation.status == .blocked)
    #expect(validation.validationArtifactPath == ".xcircuite/runs/run-1/review/decision-packet-validation.json")
    #expect(validation.diagnostics.contains {
        $0.code == "decision-packet-run-manifest-unreadable"
    })

    let storedValidation = try store.readJSON(
        FlowRunDecisionPacketValidationResult.self,
        from: root.appending(path: ".xcircuite/runs/run-1/review/decision-packet-validation.json")
    )
    #expect(storedValidation.status == .blocked)
}

@Test func decisionPacketBlocksRequiredArtifactWithoutIntegrity() throws {
    let root = try makeTemporaryRoot("agent-decision-packet-unverified-artifact")
    defer { removeTemporaryRoot(root) }
    let store = XcircuitePackageStore()
    try store.createPackage(at: root)
    _ = try store.createRunDirectory(for: "run-1", inProjectAt: root)

    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let bundle = FlowRunReviewBundle(
        runID: "run-1",
        status: .succeeded,
        runDirectoryPath: ".xcircuite/runs/run-1",
        summary: FlowRunLedgerSummary(
            runID: "run-1",
            status: .succeeded,
            runDirectoryPath: ".xcircuite/runs/run-1",
            stages: [
                FlowRunStageSummary(
                    stageID: "001-drc",
                    status: .succeeded,
                    artifactCount: 2
                ),
            ]
        ),
        artifacts: [
            FlowRunReviewArtifact(
                role: "run-manifest",
                artifactID: "run-manifest",
                path: ".xcircuite/runs/run-1/manifest.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            FlowRunReviewArtifact(
                role: "toolchain",
                artifactID: "toolchain",
                path: ".xcircuite/runs/run-1/toolchain.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            FlowRunReviewArtifact(
                role: "stage-result",
                artifactID: "001-drc-result",
                stageID: "001-drc",
                path: ".xcircuite/runs/run-1/stages/001-drc/result.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            FlowRunReviewArtifact(
                role: "stage-summary",
                artifactID: "drc-summary",
                stageID: "001-drc",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ]
    )

    let result = try DefaultFlowRunDecisionPacketBuilder(
        reviewBundler: StaticReviewBundler(bundle: bundle)
    ).buildDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    let stageSummaryRequirement = try #require(result.packet.requiredArtifacts.first {
        $0.role == "stage-summary"
    })
    #expect(result.packet.readiness == .blocked)
    #expect(stageSummaryRequirement.status == .invalid)
    #expect(stageSummaryRequirement.artifactPaths == [summaryPath])
    #expect(stageSummaryRequirement.diagnosticCodes.contains("decision-packet-required-artifact-unverified"))
    #expect(result.packet.completionIssues.contains {
        $0.code == "required-artifact-invalid"
            && $0.artifactRole == "stage-summary"
            && $0.artifactPaths == [summaryPath]
    })
}

@Test func decisionPacketValidatorBlocksReadinessMismatchEvenWithVerifiedPacket() throws {
    let root = try makeTemporaryRoot("agent-decision-packet-readiness-mismatch")
    defer { removeTemporaryRoot(root) }
    let store = XcircuitePackageStore()
    try store.createPackage(at: root)
    _ = try store.createRunDirectory(for: "run-1", inProjectAt: root)

    let bundle = FlowRunReviewBundle(
        runID: "run-1",
        status: .succeeded,
        runDirectoryPath: ".xcircuite/runs/run-1",
        summary: FlowRunLedgerSummary(
            runID: "run-1",
            status: .succeeded,
            runDirectoryPath: ".xcircuite/runs/run-1",
            stages: [
                FlowRunStageSummary(
                    stageID: "001-drc",
                    status: .succeeded,
                    artifactCount: 2
                ),
            ]
        ),
        artifacts: [
            FlowRunReviewArtifact(
                role: "run-manifest",
                artifactID: "run-manifest",
                path: ".xcircuite/runs/run-1/manifest.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            FlowRunReviewArtifact(
                role: "toolchain",
                artifactID: "toolchain",
                path: ".xcircuite/runs/run-1/toolchain.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            FlowRunReviewArtifact(
                role: "stage-result",
                artifactID: "001-drc-result",
                stageID: "001-drc",
                path: ".xcircuite/runs/run-1/stages/001-drc/result.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            FlowRunReviewArtifact(
                role: "stage-summary",
                artifactID: "drc-summary",
                stageID: "001-drc",
                path: ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
        ]
    )

    let build = try DefaultFlowRunDecisionPacketBuilder(
        reviewBundler: StaticReviewBundler(bundle: bundle)
    ).buildDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )
    #expect(build.packet.readiness == .ready)
    #expect(build.packet.completionIssues.isEmpty)

    var tampered = build.packet
    tampered.readiness = .needsReview
    let packetPath = ".xcircuite/runs/run-1/review/decision-packet.json"
    try store.writeJSON(
        tampered,
        to: root.appending(path: packetPath),
        forProjectAt: root
    )
    let reference = try store.fileReference(
        forProjectRelativePath: packetPath,
        artifactID: DefaultFlowRunDecisionPacketBuilder.artifactID,
        kind: .report,
        format: .json,
        inProjectAt: root,
        producedByRunID: "run-1"
    )
    try store.upsertRunArtifact(reference, runID: "run-1", inProjectAt: root)

    let validation = try DefaultFlowRunDecisionPacketValidator().validateDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    #expect(validation.status == .blocked)
    #expect(validation.packetArtifactIntegrity?.status == .verified)
    #expect(validation.diagnostics.contains {
        $0.code == "decision-packet-readiness-inconsistent"
    })
}

}

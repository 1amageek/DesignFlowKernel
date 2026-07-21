import CircuiteFoundation
import Foundation
import Testing
import ToolQualification
import DesignFlowKernel

private struct StaticReviewBundler: FlowRunReviewBundling {
    var bundle: FlowRunReviewBundle

    func makeReviewBundle(runID: String, workspaceID: FlowWorkspaceID) throws -> FlowRunReviewBundle {
        bundle
    }
}

enum DecisionPacketReferenceMismatch: String, CaseIterable, Sendable {
    case differentDirectory
    case arbitraryPrefix
    case inputRole
    case otherKind
    case textFormat
    case wrongContentDigestPath

    func locator(for reference: ArtifactReference) throws -> ArtifactLocator {
        let path: String
        let role: ArtifactRole
        let kind: ArtifactKind
        let format: ArtifactFormat
        switch self {
        case .differentDirectory:
            path = ".xcircuite/runs/run-1/reports/decision-packet.json"
            role = .output
            kind = .report
            format = .json
        case .arbitraryPrefix:
            path = "evil/runs/run-1/review/decision-packet.json"
            role = .output
            kind = .report
            format = .json
        case .inputRole:
            path = reference.path
            role = .input
            kind = .report
            format = .json
        case .otherKind:
            path = reference.path
            role = .output
            kind = .other
            format = .json
        case .textFormat:
            path = reference.path
            role = .output
            kind = .report
            format = .text
        case .wrongContentDigestPath:
            path = ".xcircuite/runs/run-1/review/decision-packet-sha256-\(String(repeating: "0", count: 64)).json"
            role = .output
            kind = .report
            format = .json
        }
        return ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: role,
            kind: kind,
            format: format
        )
    }
}

private func advancingRevision(of manifest: FlowRunManifest) throws -> FlowRunManifest {
    try FlowRunManifest(
        runID: manifest.runID,
        status: manifest.status,
        revision: manifest.revision + 1,
        actor: manifest.actor,
        intent: manifest.intent,
        parentRunID: manifest.parentRunID,
        createdAt: manifest.createdAt,
        updatedAt: max(Date(), manifest.updatedAt),
        startedAt: manifest.startedAt,
        finishedAt: manifest.finishedAt,
        artifacts: manifest.artifacts
    )
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
            TestArtifactReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: summaryPayload]
    )

    let result = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(result.artifact.artifactID == "review-decision-packet")
    #expect(result.artifact.path == ".xcircuite/runs/run-1/review/decision-packet.json")
    #expect(result.packet.schemaVersion == 3)
    #expect(result.packet.reviewBundle.schemaVersion == 3)
    #expect(result.packet.readiness == .needsReview)
    #expect(result.packet.requiredArtifacts.contains {
        $0.role == "stage-summary" && $0.status == .satisfied
    })
    #expect(result.packet.unresolvedReviewItems.contains {
        $0.kind == .approvalGate && $0.status == .needsReview
    })
    #expect(result.packet.replayActions.contains {
        $0.operation == .reviewRun && $0.readiness == .ready && $0.runID == "run-1"
    })

    let storedPacket = try await TestFlowInfrastructure.bound(to: root).readJSON(
        FlowRunDecisionPacket.self,
        from: root.appending(path: ".xcircuite/runs/run-1/review/decision-packet.json")
    )
    #expect(storedPacket.packetID == "decision-packet-run-1")

    let manifest = try await TestFlowInfrastructure.bound(to: root).readJSON(
        FlowRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
    )
    #expect(manifest.artifacts.contains {
        $0.artifactID == "review-decision-packet"
            && $0.path == ".xcircuite/runs/run-1/review/decision-packet.json"
    })
}

@Test func decisionPacketBuilderEmitsPacketResult() async throws {
    let root = try makeTemporaryRoot("agent-decision-packet-cli")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let summaryPayload = Data(#"{"artifactID":"drc-summary"}"#.utf8)
    try await createBlockedApprovalRun(
        root: root,
        runID: "run-1",
        artifacts: [
            TestArtifactReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: summaryPayload]
    )

    let result = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

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
            TestArtifactReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: summaryPayload]
    )
    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    let validation = try await makeTestDecisionPacketValidator(projectRoot: root).validateDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(validation.status == .needsReview)
    #expect(validation.packetReadiness == .needsReview)
    #expect(validation.packetArtifactIntegrity?.status == .verified)
    #expect(validation.requiredArtifactCount > 0)
    #expect(validation.unresolvedReviewItemCount == 1)
    #expect(validation.completionIssueCount == 1)
    #expect(validation.validationArtifactPath == "runs/run-1/review/decision-packet-validation.json")
    #expect(validation.diagnostics.contains {
        $0.code == "decision-packet-unresolved-review-item"
    })

    let manifest = try await TestFlowInfrastructure.bound(to: root).readJSON(
        FlowRunManifest.self,
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
    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    _ = try await makeTestApprovalRecorder(projectRoot: root).recordApproval(
        FlowGateApprovalRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: "run-1",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1"
        )
    )

    let validation = try await makeTestDecisionPacketValidator(projectRoot: root).validateDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
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

@Test func decisionPacketValidationReportsBlockedStatus() async throws {
    let root = try makeTemporaryRoot("agent-decision-packet-process-exit")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let validation = try await makeTestDecisionPacketValidator(projectRoot: root).validateDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(validation.status == .blocked)
}

	@Test func decisionPacketValidatorBlocksMissingPacketWithDiagnostics() async throws {
	    let root = try makeTemporaryRoot("agent-decision-packet-validation-cli")
	    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")

    let validation = try await makeTestDecisionPacketValidator(projectRoot: root).validateDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(validation.status == .blocked)
	    #expect(validation.validationArtifactPath == "runs/run-1/review/decision-packet-validation.json")
    #expect(validation.diagnostics.contains {
        $0.code == "decision-packet-artifact-reference-missing"
    })
	    #expect(validation.diagnostics.contains {
	        $0.code == "decision-packet-unreadable"
	    })
	}

	@Test func decisionPacketValidatorRejectsWrongArtifactIdentityAtLegacyPath() async throws {
	    let root = try makeTemporaryRoot("agent-decision-packet-reference-mismatch")
	    defer { removeTemporaryRoot(root) }
	    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
	    try await createBlockedApprovalRun(
	        root: root,
	        runID: "run-1",
	        artifacts: [
	            TestArtifactReference(
	                artifactID: "drc-summary",
	                path: summaryPath,
	                kind: .report,
	                format: .json
	            ),
	        ],
	        artifactPayloads: [summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8)]
	    )
	    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
	        runID: "run-1",
	        workspaceID: try testWorkspaceID(for: root)
	    )

	    let store = await TestFlowInfrastructure.bound(to: root)
	    let manifest = try await store.loadRunManifest(runID: "run-1", inProjectAt: root)
	    let packetPath = ".xcircuite/runs/run-1/review/decision-packet.json"
	    let originalReference = try #require(manifest.artifacts.first {
	        $0.path == packetPath
	    })
	    let mismatchedReference = ArtifactReference(
	        id: try ArtifactID(rawValue: "wrong-decision-packet"),
	        locator: originalReference.locator,
	        digest: originalReference.digest,
	        byteCount: originalReference.byteCount,
	        producer: originalReference.producer
	    )
	    _ = try await store.upsertRunArtifacts(
	        [mismatchedReference],
	        runID: "run-1",
	        inProjectAt: root
	    )

	    let validation = try await makeTestDecisionPacketValidator(projectRoot: root).validateDecisionPacket(
	        runID: "run-1",
	        workspaceID: try testWorkspaceID(for: root)
	    )

	    #expect(validation.status == .blocked)
	    #expect(validation.packetArtifactIntegrity == nil)
	    #expect(validation.diagnostics.contains {
	        $0.code == "decision-packet-artifact-reference-missing"
	    })
	    #expect(validation.diagnostics.contains {
	        $0.code == "decision-packet-unreadable"
	    })
	}

    @Test(arguments: DecisionPacketReferenceMismatch.allCases)
    func decisionPacketValidatorRejectsMismatchedReferenceBinding(
        mismatch: DecisionPacketReferenceMismatch
    ) async throws {
        let root = try makeTemporaryRoot("decision-packet-binding-\(mismatch.rawValue)")
        defer { removeTemporaryRoot(root) }
        try await createBlockedApprovalRun(root: root, runID: "run-1")
        _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
            runID: "run-1",
            workspaceID: try testWorkspaceID(for: root)
        )
        let store = await TestFlowInfrastructure.bound(to: root)
        var ledger = try await store.loadRunLedger(runID: "run-1")
        let original = try #require(ledger.artifacts.first {
            $0.artifactID == DefaultFlowRunDecisionPacketBuilder.artifactID
        })
        let locator = try mismatch.locator(for: original)
        let mismatched = ArtifactReference(
            id: original.id,
            locator: locator,
            digest: original.digest,
            byteCount: original.byteCount,
            producer: original.producer
        )
        ledger.artifacts.removeAll {
            $0.artifactID == DefaultFlowRunDecisionPacketBuilder.artifactID
        }
        ledger.artifacts.append(mismatched)
        ledger.runManifest = try advancingRevision(of: ledger.runManifest)
        _ = try await store.saveRunLedger(ledger)

        let validation = try await makeTestDecisionPacketValidator(
            projectRoot: root
        ).validateDecisionPacket(
            runID: "run-1",
            workspaceID: try testWorkspaceID(for: root)
        )

        #expect(validation.status == .blocked)
        #expect(validation.packetArtifactIntegrity == nil)
        #expect(validation.diagnostics.contains {
            $0.code == "decision-packet-artifact-reference-mismatch"
        })
    }

    @Test func decisionPacketValidatorAcceptsDigestBoundContentAddressedPath() async throws {
        let root = try makeTemporaryRoot("decision-packet-content-addressed")
        defer { removeTemporaryRoot(root) }
        try await createBlockedApprovalRun(root: root, runID: "run-1")
        _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
            runID: "run-1",
            workspaceID: try testWorkspaceID(for: root)
        )
        let store = await TestFlowInfrastructure.bound(to: root)
        var ledger = try await store.loadRunLedger(runID: "run-1")
        let original = try #require(ledger.artifacts.first {
            $0.artifactID == DefaultFlowRunDecisionPacketBuilder.artifactID
        })
        let content = try await store.loadArtifactContent(for: original)
        let path = ".xcircuite/runs/run-1/review/decision-packet-\(original.digest.algorithm.rawValue)-\(original.digest.hexadecimalValue).json"
        try content.write(to: root.appending(path: path), options: .atomic)
        let contentAddressed = ArtifactReference(
            id: original.id,
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: original.digest,
            byteCount: original.byteCount,
            producer: original.producer
        )
        ledger.artifacts.removeAll {
            $0.artifactID == DefaultFlowRunDecisionPacketBuilder.artifactID
        }
        ledger.artifacts.append(contentAddressed)
        ledger.runManifest = try advancingRevision(of: ledger.runManifest)
        _ = try await store.saveRunLedger(ledger)

        let validation = try await makeTestDecisionPacketValidator(
            projectRoot: root
        ).validateDecisionPacket(
            runID: "run-1",
            workspaceID: try testWorkspaceID(for: root)
        )

        #expect(validation.packetArtifactIntegrity?.status == .verified)
        #expect(!validation.diagnostics.contains {
            $0.code == "decision-packet-artifact-reference-mismatch"
        })
        #expect(validation.packetPath == path)
    }

	@Test func decisionPacketValidatorBlocksUnreadableRunManifestWithDiagnostics() async throws {
	    let root = try makeTemporaryRoot("agent-decision-packet-validation-missing-manifest")
    defer { removeTemporaryRoot(root) }
    let store = await TestFlowInfrastructure.bound(to: root)
    try await store.createWorkspace(at: root)
    let runDirectory = root.appending(path: ".xcircuite/runs/run-1", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

    let validation = try await makeTestDecisionPacketValidator(projectRoot: root).validateDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(validation.status == .blocked)
    #expect(validation.validationArtifactPath == "runs/run-1/review/decision-packet-validation.json")
    #expect(validation.diagnostics.contains {
        $0.code == "decision-packet-run-manifest-unreadable"
    })

    let storedValidation = try await store.readJSON(
        FlowRunDecisionPacketValidationResult.self,
        from: root.appending(path: ".xcircuite/runs/run-1/review/decision-packet-validation.json")
    )
    #expect(storedValidation.status == .blocked)
}

@Test func decisionPacketBlocksRequiredArtifactWithoutIntegrity() async throws {
    let root = try makeTemporaryRoot("agent-decision-packet-unverified-artifact")
    defer { removeTemporaryRoot(root) }
    let store = await TestFlowInfrastructure.bound(to: root)
    try await store.createWorkspace(at: root)
    _ = try await store.createRunDirectory(for: "run-1", inProjectAt: root)

    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let bundle = FlowRunReviewBundle(
        runID: "run-1",
        status: .succeeded,
        summary: FlowRunLedgerSummary(
            runID: "run-1",
            status: .succeeded,
            stages: [
                FlowRunStageSummary(
                    stageID: "001-drc",
                    status: .succeeded,
                    artifactCount: 2
                ),
            ]
        ),
        artifacts: [
            try makeTestReviewArtifact(
                purpose: .runManifest,
                artifactID: "run-manifest",
                path: ".xcircuite/runs/run-1/manifest.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            try makeTestReviewArtifact(
                purpose: .toolchain,
                artifactID: "toolchain",
                path: ".xcircuite/runs/run-1/toolchain.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            try makeTestReviewArtifact(
                purpose: .stageResult,
                artifactID: "001-drc-result",
                stageID: "001-drc",
                path: ".xcircuite/runs/run-1/stages/001-drc/result.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            try makeTestReviewArtifact(
                purpose: .stageSummary,
                artifactID: "drc-summary",
                stageID: "001-drc",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ]
    )

    let result = try await DefaultFlowRunDecisionPacketBuilder(
        reviewBundler: StaticReviewBundler(bundle: bundle),
        persistence: store
    ).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
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

@Test func decisionPacketValidatorBlocksReadinessMismatchEvenWithVerifiedPacket() async throws {
    let root = try makeTemporaryRoot("agent-decision-packet-readiness-mismatch")
    defer { removeTemporaryRoot(root) }
    let store = await TestFlowInfrastructure.bound(to: root)
    try await store.createWorkspace(at: root)
    _ = try await store.createRunDirectory(for: "run-1", inProjectAt: root)

    let bundle = FlowRunReviewBundle(
        runID: "run-1",
        status: .succeeded,
        summary: FlowRunLedgerSummary(
            runID: "run-1",
            status: .succeeded,
            stages: [
                FlowRunStageSummary(
                    stageID: "001-drc",
                    status: .succeeded,
                    artifactCount: 2
                ),
            ]
        ),
        artifacts: [
            try makeTestReviewArtifact(
                purpose: .runManifest,
                artifactID: "run-manifest",
                path: ".xcircuite/runs/run-1/manifest.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            try makeTestReviewArtifact(
                purpose: .toolchain,
                artifactID: "toolchain",
                path: ".xcircuite/runs/run-1/toolchain.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            try makeTestReviewArtifact(
                purpose: .stageResult,
                artifactID: "001-drc-result",
                stageID: "001-drc",
                path: ".xcircuite/runs/run-1/stages/001-drc/result.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
            try makeTestReviewArtifact(
                purpose: .stageSummary,
                artifactID: "drc-summary",
                stageID: "001-drc",
                path: ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json",
                kind: .report,
                format: .json,
                integrity: verifiedTestIntegrity()
            ),
        ]
    )

    let build = try await DefaultFlowRunDecisionPacketBuilder(
        reviewBundler: StaticReviewBundler(bundle: bundle),
        persistence: store
    ).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )
    #expect(build.packet.readiness == .ready)
    #expect(build.packet.completionIssues.isEmpty)

    var tampered = build.packet
    tampered.readiness = .needsReview
    let packetPath = ".xcircuite/runs/run-1/review/decision-packet.json"
    try await store.writeJSON(
        tampered,
        to: root.appending(path: packetPath),
        forProjectAt: root
    )
    let reference = try await store.fileReference(
        forProjectRelativePath: packetPath,
        artifactID: DefaultFlowRunDecisionPacketBuilder.artifactID,
        kind: .report,
        format: .json,
        inProjectAt: root,
        producerRunID: "run-1"
    )
    try await store.upsertRunArtifact(reference, runID: "run-1", inProjectAt: root)

    let validation = try await makeTestDecisionPacketValidator(projectRoot: root).validateDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(validation.status == .blocked)
    #expect(validation.packetArtifactIntegrity?.status == .verified)
    #expect(validation.diagnostics.contains {
        $0.code == "decision-packet-readiness-inconsistent"
    })
}

}

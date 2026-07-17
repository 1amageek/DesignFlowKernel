import DesignFlowKernel
import CircuiteFoundation
import Foundation
import Testing
import ToolQualification
import DesignFlowKernel

extension FlowRunLedgerSummaryTests {
@Test func stageArtifactLadderBuilderPersistsStageOrderedArtifactsAndRegistersRunArtifact() async throws {
    let root = try makeTemporaryRoot("stage-artifact-ladder")
    defer { removeTemporaryRoot(root) }
    let runID = "run-1"

    let editPath = ".xcircuite/runs/\(runID)/stages/001-edit/raw/design-diff.json"
    let exportPath = ".xcircuite/runs/\(runID)/stages/002-export/raw/layout.oas"
    let drcPath = ".xcircuite/runs/\(runID)/stages/003-drc/raw/drc-summary.json"
    let lvsPath = ".xcircuite/runs/\(runID)/stages/004-lvs/raw/lvs-summary.json"
    let pexPath = ".xcircuite/runs/\(runID)/stages/005-pex/raw/pex-summary.json"
    let postLayoutPath = ".xcircuite/runs/\(runID)/stages/006-post-layout/raw/post-layout-comparison.json"
    let reviewPath = ".xcircuite/runs/\(runID)/stages/007-review/raw/review-summary.json"

    _ = try await makeTestOrchestrator(projectRoot: root).run(
        request: FlowOperationRequest(
            workspaceID: try testWorkspaceID(for: root),
            runID: runID,
            intent: "Build generated layout signoff ladder",
            stages: [
                FlowStageDefinition(stageID: "001-edit", displayName: "Edit"),
                FlowStageDefinition(stageID: "002-export", displayName: "Export"),
                FlowStageDefinition(
                    stageID: "003-drc",
                    displayName: "DRC",
                    retryPolicy: FlowStageRetryPolicy(
                        maxAttempts: 2,
                        retryableDiagnosticCodes: ["TRANSIENT_DRC_FAILURE"]
                    )
                ),
                FlowStageDefinition(stageID: "004-lvs", displayName: "LVS"),
                FlowStageDefinition(stageID: "005-pex", displayName: "PEX"),
                FlowStageDefinition(stageID: "006-post-layout", displayName: "Post-layout comparison"),
                FlowStageDefinition(stageID: "007-review", displayName: "Review", requiresApproval: true),
            ]
        ),
        toolRegistry: ToolRegistry(),
        healthResults: [:],
        executors: [
            SummaryStageExecutor(
                stageID: "001-edit",
                toolID: "edit-tool",
                status: .succeeded,
                artifacts: [
                    TestArtifactReference(
                        artifactID: "edit-design-diff",
                        path: editPath,
                        kind: .designDiff,
                        format: .json
                    ),
                ],
                artifactPayloads: [editPath: Data(#"{"changeCount":1}"#.utf8)]
            ),
            SummaryStageExecutor(
                stageID: "002-export",
                toolID: "export-tool",
                status: .succeeded,
                artifacts: [
                    TestArtifactReference(
                        artifactID: "layout-oasis-export",
                        path: exportPath,
                        kind: .layout,
                        format: .oasis
                    ),
                ],
                artifactPayloads: [exportPath: Data("OASIS".utf8)]
            ),
            SummaryStageExecutor(
                stageID: "003-drc",
                toolID: "drc-tool",
                status: .succeeded,
                artifacts: [
                    TestArtifactReference(
                        artifactID: "drc-summary",
                        path: drcPath,
                        kind: .report,
                        format: .json
                    ),
                ],
                artifactPayloads: [drcPath: Data(#"{"violationCount":0}"#.utf8)]
            ),
            SummaryStageExecutor(
                stageID: "004-lvs",
                toolID: "lvs-tool",
                status: .succeeded,
                artifacts: [
                    TestArtifactReference(
                        artifactID: "lvs-summary",
                        path: lvsPath,
                        kind: .report,
                        format: .json
                    ),
                ],
                artifactPayloads: [lvsPath: Data(#"{"mismatchCount":0}"#.utf8)]
            ),
            SummaryStageExecutor(
                stageID: "005-pex",
                toolID: "pex-tool",
                status: .succeeded,
                artifacts: [
                    TestArtifactReference(
                        artifactID: "pex-summary",
                        path: pexPath,
                        kind: .parasitics,
                        format: .json
                    ),
                ],
                artifactPayloads: [pexPath: Data(#"{"netCount":1}"#.utf8)]
            ),
            SummaryStageExecutor(
                stageID: "006-post-layout",
                toolID: "post-layout-tool",
                status: .succeeded,
                artifacts: [
                    TestArtifactReference(
                        artifactID: "post-layout-comparison-summary",
                        path: postLayoutPath,
                        kind: .measurement,
                        format: .json
                    ),
                ],
                artifactPayloads: [postLayoutPath: Data(#"{"maxDelta":0.0}"#.utf8)]
            ),
            SummaryStageExecutor(
                stageID: "007-review",
                toolID: "review-tool",
                status: .succeeded,
                artifacts: [
                    TestArtifactReference(
                        artifactID: "review-summary",
                        path: reviewPath,
                        kind: .report,
                        format: .json
                    ),
                ],
                artifactPayloads: [reviewPath: Data(#"{"reviewState":"pending"}"#.utf8)]
            ),
        ]
    )

    let result = try await makeTestStageArtifactLadderBuilder(projectRoot: root).buildStageArtifactLadder(
        runID: runID,
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(result.artifact.artifactID == "review-stage-artifact-ladder")
    #expect(result.artifact.path == ".xcircuite/runs/\(runID)/review/stage-artifact-ladder.json")
    #expect(result.ladder.runID == runID)
    #expect(result.ladder.readiness == .needsReview)
    #expect(result.ladder.stages.map(\.stageID) == [
        "001-edit",
        "002-export",
        "003-drc",
        "004-lvs",
        "005-pex",
        "006-post-layout",
        "007-review",
    ])
    #expect(result.ladder.summary.retryArtifactCount == 1)
    #expect((result.ladder.summary.domainCounts["edit"] ?? 0) > 0)
    #expect((result.ladder.summary.domainCounts["export"] ?? 0) > 0)
    #expect((result.ladder.summary.domainCounts["drc"] ?? 0) > 0)
    #expect((result.ladder.summary.domainCounts["lvs"] ?? 0) > 0)
    #expect((result.ladder.summary.domainCounts["pex"] ?? 0) > 0)
    #expect((result.ladder.summary.domainCounts["postLayoutComparison"] ?? 0) > 0)
    #expect((result.ladder.summary.stageCategoryCounts?["edit"] ?? 0) == 1)
    #expect((result.ladder.summary.stageCategoryCounts?["export"] ?? 0) == 1)
    #expect((result.ladder.summary.stageCategoryCounts?["drc"] ?? 0) == 1)
    #expect((result.ladder.summary.stageCategoryCounts?["lvs"] ?? 0) == 1)
    #expect((result.ladder.summary.stageCategoryCounts?["pex"] ?? 0) == 1)
    #expect((result.ladder.summary.stageCategoryCounts?["postLayoutComparison"] ?? 0) == 1)
    #expect((result.ladder.summary.handoffRefCount ?? 0) >= 7)
    #expect(result.ladder.summary.statusRefCount == 7)
    let signoffCoverage = try #require(result.ladder.signoffManifestCoverage)
    #expect(signoffCoverage.missingRoles.isEmpty)
    #expect(signoffCoverage.unsignedArtifactPaths.isEmpty)
    #expect(signoffCoverage.allRequiredArtifactsHaveHashesAndByteCounts)
    #expect(Set(signoffCoverage.satisfiedRoles) == Set(signoffCoverage.requiredRoles))
    #expect(signoffCoverage.artifactPathsByRole["generated-layout"]?.contains(exportPath) == true)
    #expect(signoffCoverage.artifactPathsByRole["signoff-input"]?.contains(exportPath) == true)
    #expect(signoffCoverage.artifactPathsByRole["signoff-summary"]?.contains(drcPath) == true)
    #expect(signoffCoverage.artifactPathsByRole["signoff-summary"]?.contains(lvsPath) == true)
    #expect(signoffCoverage.artifactPathsByRole["signoff-summary"]?.contains(pexPath) == true)
    #expect(signoffCoverage.artifactPathsByRole["post-layout-report"]?.contains(postLayoutPath) == true)
    #expect(signoffCoverage.artifactPathsByRole["review-ref"]?.contains(reviewPath) == true)
    #expect(signoffCoverage.artifactPathsByRole["run-manifest"]?.contains(".xcircuite/runs/\(runID)/manifest.json") == true)

    let drcStage = try #require(result.ladder.stages.first { $0.stageID == "003-drc" })
    #expect(drcStage.category == "drc")
    #expect(drcStage.statusRef == "runs/\(runID)/stages/003-drc/result.json")
    #expect(drcStage.domains.contains("drc"))
    #expect(drcStage.domains.contains("retry"))
    #expect(drcStage.artifacts.contains {
        $0.role == "stage-attempts"
            && $0.domain == "retry"
            && $0.path == ".xcircuite/runs/\(runID)/stages/003-drc/attempts.json"
    })
    #expect(drcStage.artifacts.contains {
        $0.domain == "drc"
            && $0.handoffRole == "stage-output"
            && $0.statusRef == "runs/\(runID)/stages/003-drc/result.json"
    })
    #expect(drcStage.handoffRefs?.contains {
        $0.fromStageID == "003-drc"
            && $0.toStageID == "004-lvs"
            && $0.domain == "drc"
            && $0.statusRef == "runs/\(runID)/stages/003-drc/result.json"
    } == true)
    #expect(drcStage.retryRefs?.contains {
        $0.stageID == "003-drc" && $0.attemptIndex == 1
    } == true)
    #expect(drcStage.roleCoverage.contains {
        $0.role == "stage-attempts" && $0.artifactCount == 1
    })

    let reviewStage = try #require(result.ladder.stages.first { $0.stageID == "007-review" })
    #expect(reviewStage.category == "review")
    #expect(reviewStage.domains.contains("review"))
    #expect(reviewStage.reviewItems.contains {
        $0.kind == .approvalGate && $0.status == .needsReview
    })
    #expect(result.ladder.replayActions.contains {
        $0.operation == .buildStageArtifactLadder && $0.readiness == .ready && $0.runID == runID
    })

    let stored = try await TestFlowInfrastructure.bound(to: root).readJSON(
        FlowRunStageArtifactLadder.self,
        from: root.appending(path: ".xcircuite/runs/\(runID)/review/stage-artifact-ladder.json")
    )
    #expect(stored.stages.map(\.stageID) == result.ladder.stages.map(\.stageID))
    #expect(stored.signoffManifestCoverage == result.ladder.signoffManifestCoverage)

    let manifest = try await TestFlowInfrastructure.bound(to: root).readJSON(
        FlowRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/\(runID)/manifest.json")
    )
    #expect(manifest.artifacts.contains {
        $0.artifactID == "review-stage-artifact-ladder"
            && $0.path == ".xcircuite/runs/\(runID)/review/stage-artifact-ladder.json"
    })
    for path in [
        editPath,
        exportPath,
        drcPath,
        lvsPath,
        pexPath,
        postLayoutPath,
        reviewPath,
        ".xcircuite/runs/\(runID)/review/stage-artifact-ladder.json",
    ] {
        let reference = try #require(manifest.artifacts.first { $0.path == path })
        #expect(!reference.digest.hexadecimalValue.isEmpty)
        #expect(reference.byteCount > 0)
    }

    let bundle = try await makeTestReviewBundler(projectRoot: root).makeReviewBundle(
        runID: runID,
        workspaceID: try testWorkspaceID(for: root)
    )
    let runManifestArtifact = try #require(bundle.artifacts.first {
        $0.purpose == .runManifest
    })
    #expect(runManifestArtifact.reference.artifactID == "run-manifest")
    #expect(!runManifestArtifact.reference.digest.hexadecimalValue.isEmpty)
    #expect(runManifestArtifact.reference.byteCount > 0)
    #expect(runManifestArtifact.integrity?.status == .verified)
    #expect(bundle.artifacts.contains {
        $0.purpose == .stageArtifactLadder
            && $0.reference.artifactID == "review-stage-artifact-ladder"
    })
}

@Test func stageArtifactLadderBuilderEmitsBuildResult() async throws {
    let root = try makeTemporaryRoot("stage-artifact-ladder-cli")
    defer { removeTemporaryRoot(root) }
    let runID = "run-1"
    let summaryPath = ".xcircuite/runs/\(runID)/stages/001-drc/raw/drc-summary.json"
    try await createBlockedApprovalRun(
        root: root,
        runID: runID,
        artifacts: [
            TestArtifactReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: Data(#"{"violationCount":0}"#.utf8)]
    )

    let result = try await makeTestStageArtifactLadderBuilder(projectRoot: root).buildStageArtifactLadder(
        runID: runID,
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(result.artifact.artifactID == "review-stage-artifact-ladder")
    #expect(result.ladder.stages.count == 1)
    #expect(result.ladder.stages.first?.artifacts.contains {
        $0.domain == "drc" && $0.role == "stage-summary"
    } == true)
    #expect(result.ladder.replayActions.contains {
        $0.operation == .reviewRun
    })
}

@Test func stageArtifactLadderBlocksUnsafeStageIdentifierAndSuppressesHandoffRefs() async throws {
    let root = try makeTemporaryRoot("stage-artifact-ladder-unsafe-stage-id")
    defer { removeTemporaryRoot(root) }
    let runID = "run-1"
    let summaryPath = ".xcircuite/runs/\(runID)/stages/001-drc/raw/drc-summary.json"
    let payload = Data(#"{"violationCount":0}"#.utf8)
    try await createBlockedApprovalRun(
        root: root,
        runID: runID,
        artifacts: [
            TestArtifactReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: payload]
    )
    let resultPath = ".xcircuite/runs/\(runID)/stages/001-drc/result.json"
    var result = try await TestFlowInfrastructure.bound(to: root).readJSON(
        FlowStageResult.self,
        from: root.appending(path: resultPath)
    )
    result.stageID = "../escape"
    try await TestFlowInfrastructure.bound(to: root).writeJSON(
        result,
        to: root.appending(path: resultPath),
        forProjectAt: root
    )

    let buildResult = try await makeTestStageArtifactLadderBuilder(projectRoot: root).buildStageArtifactLadder(
        runID: runID,
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(buildResult.ladder.readiness == .blocked)
    #expect(buildResult.ladder.summary.invalidArtifactCount > 0)
    let unsafeStage = try #require(buildResult.ladder.stages.first { $0.stageID == "../escape" })
    #expect(unsafeStage.statusRef == nil)
    #expect(unsafeStage.handoffRefs?.isEmpty == true)
    #expect(unsafeStage.artifacts.contains {
        $0.artifactID == "drc-summary" && $0.integrity?.status == .invalidIdentifier
    })
    let signoffCoverage = try #require(buildResult.ladder.signoffManifestCoverage)
    #expect(signoffCoverage.artifactPathsByRole["signoff-summary"]?.contains(summaryPath) != true)
    #expect(signoffCoverage.missingRoles.contains("signoff-summary"))
}

@Test func stageArtifactLadderBlocksHandoffAndSignoffForArtifactWithoutIntegrity() async throws {
    let root = try makeTemporaryRoot("stage-artifact-ladder-unverified-artifact")
    defer { removeTemporaryRoot(root) }
    let runID = "run-1"
    let summaryPath = ".xcircuite/runs/\(runID)/stages/001-drc/raw/drc-summary.json"
    let bundle = FlowRunReviewBundle(
        runID: runID,
        status: .succeeded,
        summary: FlowRunLedgerSummary(
            runID: runID,
            status: .succeeded,
            stages: [
                FlowRunStageSummary(
                    stageID: "001-drc",
                    status: .succeeded,
                    artifactCount: 1
                ),
            ]
        ),
        artifacts: [
            try makeTestReviewArtifact(
                purpose: .stageSummary,
                artifactID: "drc-summary",
                stageID: "001-drc",
                path: summaryPath,
                kind: .report,
                format: .json,
                sha256: String(repeating: "b", count: 64),
                byteCount: 24
            ),
        ]
    )

    let ladder = await makeTestStageArtifactLadderBuilder(projectRoot: root).makeStageArtifactLadder(
        from: bundle,
        stageResults: [],
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(ladder.readiness == .blocked)
    #expect(ladder.summary.invalidArtifactCount == 1)
    let drcStage = try #require(ladder.stages.first { $0.stageID == "001-drc" })
    #expect(drcStage.handoffRefs?.contains { $0.artifactPath == summaryPath } != true)
    #expect(drcStage.roleCoverage.contains {
        $0.role == "stage-summary"
            && $0.verifiedCount == 0
            && $0.issueCount == 1
            && $0.artifactPaths == [summaryPath]
    })
    let signoffCoverage = try #require(ladder.signoffManifestCoverage)
    #expect(signoffCoverage.artifactPathsByRole["signoff-summary"]?.contains(summaryPath) != true)
    #expect(signoffCoverage.missingRoles.contains("signoff-summary"))
    #expect(signoffCoverage.unsignedArtifactPaths == [summaryPath])
    #expect(!signoffCoverage.allRequiredArtifactsHaveHashesAndByteCounts)
}

@Test func stageArtifactLadderBlocksDuplicateStageResultsWithoutTrapping() async throws {
    let root = try makeTemporaryRoot("stage-artifact-ladder-duplicate-stage-result")
    defer { removeTemporaryRoot(root) }
    let runID = "run-1"
    let bundle = FlowRunReviewBundle(
        runID: runID,
        status: .succeeded,
        summary: FlowRunLedgerSummary(
            runID: runID,
            status: .succeeded,
            stages: [
                FlowRunStageSummary(
                    stageID: "001-drc",
                    status: .succeeded
                ),
            ]
        ),
        artifacts: []
    )

    let ladder = await makeTestStageArtifactLadderBuilder(projectRoot: root).makeStageArtifactLadder(
        from: bundle,
        stageResults: [
            FlowStageResult(stageID: "001-drc", status: .succeeded),
            FlowStageResult(stageID: "001-drc", status: .failed),
        ],
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(ladder.readiness == .blocked)
    let drcStage = try #require(ladder.stages.first { $0.stageID == "001-drc" })
    #expect(drcStage.diagnosticCodes.contains("stage-artifact-ladder-duplicate-stage-result"))
}

@Test func stageArtifactLadderRejectsIncompleteCurrentSchema() throws {
    let payload = Data(
        """
        {
          "runID": "run-1",
          "status": "succeeded",
          "summary": {
            "stageCount": 1
          },
          "stages": [
            {
              "stageID": "001-drc",
              "status": "succeeded",
              "artifacts": [
                {
                  "role": "stage-summary",
                  "domain": "drc",
                  "path": ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json",
                  "kind": "report",
                  "format": "JSON"
                }
              ],
              "roleCoverage": [
                {
                  "role": "stage-summary"
                }
              ],
              "retryRefs": [
                {
                  "stageID": "001-drc",
                  "attemptIndex": 1,
                  "status": "failed",
                  "shouldRetry": true,
                  "reason": "retryableDiagnosticMatched"
                }
              ]
            }
          ],
          "signoffManifestCoverage": {
            "requiredRoles": ["signoff-summary"],
            "satisfiedRoles": ["signoff-summary"],
            "missingRoles": []
          }
        }
        """.utf8
    )

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(FlowRunStageArtifactLadder.self, from: payload)
    }
}

}

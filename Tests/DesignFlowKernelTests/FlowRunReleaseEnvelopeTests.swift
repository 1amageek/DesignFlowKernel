import CircuiteFoundation
import Foundation
import Testing
import ToolQualification
import DesignFlowKernel

extension FlowRunLedgerSummaryTests {
@Test func releaseEnvelopeBuilderPersistsBlockedEnvelopeAndRegistersRunArtifact() async throws {
    let root = try makeTemporaryRoot("agent-release-envelope")
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
    let store = await TestFlowInfrastructure.bound(to: root)
    let reviewBundler = DefaultFlowRunReviewBundler(loader: store, persistence: store)
    _ = try await DefaultFlowRunDecisionPacketBuilder(
        reviewBundler: reviewBundler,
        persistence: store
    ).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    let validator = DefaultFlowRunDecisionPacketValidator(
        loader: store,
        persistence: store,
        reviewBundler: reviewBundler
    )
    let result = try await DefaultFlowRunReleaseEnvelopeBuilder(
        decisionPacketValidator: validator,
        loader: store,
        persistence: store
    ).buildReleaseEnvelope(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(result.artifact.id.rawValue == "qualification-release-envelope")
    #expect(result.artifact.locator.location.value == ".xcircuite/runs/run-1/qualification/release-envelope.json")
    #expect(result.envelope.status == .blocked)
    #expect(result.envelope.requirements.contains {
        $0.requirementID == "decision-packet-validation" && $0.status == .needsReview
    })
    #expect(result.envelope.requirements.contains {
        $0.requirementID == "retained-corpus-history" && $0.status == .blocked
    })
    #expect(result.envelope.diagnostics.contains {
        $0.code == "release-envelope-corpus-history-missing"
    })

    let manifest = try await store.loadRunLedger(runID: "run-1").runManifest
    #expect(manifest.artifacts.contains {
        $0.artifactID == "qualification-release-envelope"
            && $0.path == ".xcircuite/runs/run-1/qualification/release-envelope.json"
    })
}

@Test func releaseEnvelopeBuilderReportsBlockedStatus() async throws {
    let root = try makeTemporaryRoot("agent-release-envelope-process-exit")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    let build = try await makeTestReleaseEnvelopeBuilder(projectRoot: root).buildReleaseEnvelope(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    #expect(build.envelope.status == .blocked)
}

@Test func releaseEnvelopeBuilderEmitsVerifiedReleaseEvidence() async throws {
    let root = try makeTemporaryRoot("agent-release-envelope-cli")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/release.qualification/raw/drc-summary.json"
    let corpusPath = ".xcircuite/runs/run-1/qualification/corpus-history.json"
    let performancePath = ".xcircuite/runs/run-1/qualification/performance-envelope.json"
    let contractPath = ".xcircuite/runs/run-1/qualification/contract-audit.json"
    let releaseQualificationPath = ".xcircuite/runs/run-1/stages/release.qualification/raw/result.json"
    let retentionIndexPath = ".xcircuite/runs/run-1/qualification/retention-index.json"
    let dashboardSourcePath = "retention/dashboard.json"
    let historySourcePath = "retention/history.jsonl"
    let collectedAt = ISO8601DateFormatter().string(from: Date())
    try FileManager.default.createDirectory(at: root.appending(path: "retention"), withIntermediateDirectories: true)
    try Data(#"{"schemaVersion":1,"runID":"run-1","status":"passed","history":{"status":"passed"},"retainedSignoffSuite":{"status":"passed"}}"#.utf8).write(
        to: root.appending(path: dashboardSourcePath),
        options: .atomic
    )
    var historyEntry = FlowRunReleaseHistoryEntry(
        sequence: 1,
        entryID: "entry-1",
        runID: "run-1",
        recordedAt: collectedAt,
        qualificationDigest: String(repeating: "c", count: 64),
        previousEntrySHA256: nil,
        entrySHA256: String(repeating: "0", count: 64)
    )
    historyEntry.entrySHA256 = try historyEntry.computedSHA256()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var historyData = try encoder.encode(historyEntry)
    historyData.append(Data("\n".utf8))
    try historyData.write(to: root.appending(path: historySourcePath), options: .atomic)
    let sourceDashboard = try await makeTestInputArtifactReference(
        at: root.appending(path: dashboardSourcePath),
        artifactID: "retention-source-dashboard",
        projectRoot: root
    )
    let history = try await makeTestInputArtifactReference(
        at: root.appending(path: historySourcePath),
        artifactID: "retention-source-history",
        projectRoot: root
    )
    let retentionIndex = try await makeTestRetentionIndexBuilder(projectRoot: root).build(
        runID: "run-1",
        workflowRunID: "workflow-run-1",
        workspaceID: try testWorkspaceID(for: root),
        sourceDashboard: sourceDashboard,
        history: history,
        previousEntryCount: 0,
        retentionDays: 30,
        minimumRetentionDays: 30,
        recordedAt: Date()
    )
    let retentionIndexData = try encoder.encode(retentionIndex)
    try await createBlockedApprovalRun(
        root: root,
        runID: "run-1",
        stageID: "release.qualification",
        artifacts: [
            TestArtifactReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
            TestArtifactReference(
                artifactID: "qualification-corpus-history",
                path: corpusPath,
                kind: .report,
                format: .json
            ),
            TestArtifactReference(
                artifactID: "qualification-performance-envelope",
                path: performancePath,
                kind: .report,
                format: .json
            ),
            TestArtifactReference(
                artifactID: "qualification-contract-audit",
                path: contractPath,
                kind: .report,
                format: .json
            ),
            TestArtifactReference(
                artifactID: "release-qualification-result",
                path: releaseQualificationPath,
                kind: .report,
                format: .json
            ),
            TestArtifactReference(
                artifactID: "qualification-retention-index",
                path: retentionIndexPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [
            summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8),
            corpusPath: Data("""
            {
              "schemaVersion": 1,
              "runID": "run-1",
              "collectedAt": "\(collectedAt)",
              "sourceDashboardPath": "signoff-dashboard.json",
              "sourceDashboardSHA256": "sha256",
              "dashboardStatus": "passed",
              "historyStatus": "passed",
              "previousEntryCount": 2,
              "appended": true,
              "retainedSignoffSuiteStatus": "passed",
              "domains": [
                {
                  "domain": "drc",
                  "status": "passed",
                  "previousQualifiedEntryCount": 2,
                  "currentStatus": "passed",
                  "qualified": true,
                  "caseCount": 3,
                  "passRate": 1.0,
                  "totalDurationSeconds": 1.2,
                  "coverageTagCount": 4,
                  "failureCount": 0
                }
              ],
              "diagnostics": []
            }
            """.utf8),
            performancePath: Data("""
            {
              "schemaVersion": 1,
              "runID": "run-1",
              "collectedAt": "\(collectedAt)",
              "sourceDashboardPath": "signoff-dashboard.json",
              "sourceDashboardSHA256": "sha256",
              "historyStatus": "passed",
              "maxTotalDurationRegression": 1.5,
              "domains": [
                {
                  "domain": "drc",
                  "status": "passed",
                  "currentTotalDurationSeconds": 1.2,
                  "medianTotalDurationSeconds": 1.0,
                  "maxAllowedTotalDurationSeconds": 1.5,
                  "durationRegressionRatio": 1.2,
                  "currentPassRate": 1.0,
                  "medianPassRate": 1.0,
                  "failureCount": 0
                }
              ],
              "promotionStatus": "passed",
              "promotionFailureCount": 0,
              "diagnostics": []
            }
            """.utf8),
            contractPath: Data("""
            {
              "schemaVersion": 1,
              "runID": "run-1",
              "collectedAt": "\(collectedAt)",
              "sourceReportPath": "contract-report.json",
              "sourceReportSHA256": "sha256",
              "status": "passed",
              "contractCount": 1,
              "failedContractCount": 0,
              "contracts": [
                {
                  "contractID": "xcircuite.run-manifest.v2",
                  "owner": "XcircuiteWorkspace",
                  "status": "passed",
                  "expectedVersion": 1,
                  "observedVersion": 1,
                  "requiredPathCount": 9,
                  "failureCount": 0
                }
              ],
              "diagnostics": []
            }
            """.utf8),
            releaseQualificationPath: Data("""
            {
              "schemaVersion": 1,
              "runID": "run-1",
              "status": "completed",
              "diagnostics": [],
              "metadata": {
                "completedAt": "\(collectedAt)"
              },
              "payload": {
                "schemaVersion": 1,
                "qualified": true,
                "processProfileID": "sky130",
                "qualificationLevel": "oracleChecked",
                "qualificationScope": {
                  "implementationID": "native-drc",
                  "binaryDigest": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "algorithmVersion": "native-drc-v1",
                  "processProfileID": "sky130",
                  "deckDigest": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                },
                "qualificationDigest": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                "promotionStatus": "oracleChecked",
                "promotionFailureCodes": [],
                "laneResults": [
                  {
                    "laneID": "drc:external-oracle",
                    "domain": "drc",
                    "kind": "externalOracle",
                    "status": "passed",
                    "qualified": true,
                    "caseCount": 3,
                    "coverageTagCount": 4,
                    "coveredRequiredCoverageTagCount": 4,
                    "passRate": 1.0,
                    "oracleAgreementRate": 1.0,
                    "durationBudgetPassRate": 1.0,
                    "failureCodes": []
                  }
                ],
                "blockedLanes": [],
                "failedLanes": []
              }
            }
            """.utf8),
            retentionIndexPath: retentionIndexData,
        ]
    )
    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    let result = try await makeTestReleaseEnvelopeBuilder(projectRoot: root).buildReleaseEnvelope(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )
    #expect(result.envelope.runID == "run-1")
    #expect(result.envelope.status == .needsReview)
    #expect(result.envelope.requirements.contains {
        $0.requirementID == "retained-corpus-history"
            && $0.status == .passed
            && $0.artifactIntegrity.first?.status == .verified
    })
    #expect(result.envelope.requirements.contains {
        $0.requirementID == "performance-envelope"
            && $0.status == .passed
            && $0.artifactIntegrity.first?.status == .verified
    })
    #expect(result.envelope.requirements.contains {
        $0.requirementID == "contract-audit"
            && $0.status == .passed
            && $0.artifactIntegrity.first?.status == .verified
    })
    #expect(result.envelope.requirements.contains {
        $0.requirementID == "release-qualification"
            && $0.status == .passed
            && $0.artifactIntegrity.first?.status == .verified
    })
    #expect(result.envelope.requirements.contains {
        $0.requirementID == "retention-index"
            && $0.status == .passed
            && $0.artifactIntegrity.first?.status == .verified
    })
    #expect(result.envelope.replayCommands.contains {
        $0.commandID == "build-release-envelope" && $0.readiness == .ready
    })
}

@Test func releaseEnvelopeBlocksFailedCorpusHistoryAndContractAuditContent() async throws {
    let root = try makeTemporaryRoot("agent-release-corpus-contract-content-failed")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let corpusPath = ".xcircuite/runs/run-1/qualification/corpus-history.json"
    let performancePath = ".xcircuite/runs/run-1/qualification/performance-envelope.json"
    let contractPath = ".xcircuite/runs/run-1/qualification/contract-audit.json"
    let collectedAt = ISO8601DateFormatter().string(from: Date())
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
            TestArtifactReference(
                artifactID: "qualification-corpus-history",
                path: corpusPath,
                kind: .report,
                format: .json
            ),
            TestArtifactReference(
                artifactID: "qualification-performance-envelope",
                path: performancePath,
                kind: .report,
                format: .json
            ),
            TestArtifactReference(
                artifactID: "qualification-contract-audit",
                path: contractPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [
            summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8),
            corpusPath: Data("""
            {
              "schemaVersion": 1,
              "runID": "run-1",
              "collectedAt": "\(collectedAt)",
              "sourceDashboardPath": "signoff-dashboard.json",
              "sourceDashboardSHA256": "sha256",
              "dashboardStatus": "failed",
              "historyStatus": "skipped",
              "previousEntryCount": 0,
              "appended": false,
              "retainedSignoffSuiteStatus": "failed",
              "domains": [
                {
                  "domain": "drc",
                  "status": "failed",
                  "previousQualifiedEntryCount": 0,
                  "currentStatus": "failed",
                  "qualified": false,
                  "caseCount": 0,
                  "passRate": 0.5,
                  "totalDurationSeconds": 4.0,
                  "coverageTagCount": 0,
                  "failureCount": 1
                }
              ],
              "diagnostics": [
                {
                  "severity": "error",
                  "code": "release-corpus-dashboard-not-passed",
                  "message": "Signoff qualification dashboard status is not passed."
                }
              ]
            }
            """.utf8),
            performancePath: Data("""
            {
              "schemaVersion": 1,
              "runID": "run-1",
              "collectedAt": "\(collectedAt)",
              "sourceDashboardPath": "signoff-dashboard.json",
              "sourceDashboardSHA256": "sha256",
              "historyStatus": "passed",
              "maxTotalDurationRegression": 1.5,
              "domains": [
                {
                  "domain": "drc",
                  "status": "passed",
                  "currentTotalDurationSeconds": 1.2,
                  "medianTotalDurationSeconds": 1.0,
                  "maxAllowedTotalDurationSeconds": 1.5,
                  "durationRegressionRatio": 1.2,
                  "currentPassRate": 1.0,
                  "medianPassRate": 1.0,
                  "failureCount": 0
                }
              ],
              "promotionStatus": "passed",
              "promotionFailureCount": 0,
              "diagnostics": []
            }
            """.utf8),
            contractPath: Data("""
            {
              "schemaVersion": 1,
              "runID": "run-1",
              "collectedAt": "\(collectedAt)",
              "sourceReportPath": "contract-report.json",
              "sourceReportSHA256": "sha256",
              "status": "failed",
              "contractCount": 1,
              "failedContractCount": 1,
              "contracts": [
                {
                  "contractID": "xcircuite.run-manifest.v2",
                  "owner": "XcircuiteWorkspace",
                  "status": "failed",
                  "expectedVersion": 1,
                  "observedVersion": 2,
                  "requiredPathCount": 0,
                  "failureCount": 1
                }
              ],
              "diagnostics": [
                {
                  "severity": "error",
                  "code": "release-contract-audit-not-passed",
                  "message": "Versioned contract fixture report status is not passed."
                }
              ]
            }
            """.utf8),
        ]
    )
    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    let envelope = try await makeTestReleaseEnvelopeBuilder(projectRoot: root).buildReleaseEnvelope(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    ).envelope

    #expect(envelope.status == .blocked)
    let corpusRequirement = try #require(envelope.requirements.first {
        $0.requirementID == "retained-corpus-history"
    })
    #expect(corpusRequirement.status == .blocked)
    #expect(corpusRequirement.artifactIntegrity.first?.status == .verified)
    #expect(corpusRequirement.diagnosticCodes.contains("release-envelope-corpus-dashboard-not-passed"))
    #expect(corpusRequirement.diagnosticCodes.contains("release-envelope-corpus-history-not-passed"))
    #expect(corpusRequirement.diagnosticCodes.contains("release-envelope-corpus-domain-unqualified"))
    #expect(corpusRequirement.diagnosticCodes.contains("release-envelope-corpus-domain-pass-rate-below-one"))

    let contractRequirement = try #require(envelope.requirements.first {
        $0.requirementID == "contract-audit"
    })
    #expect(contractRequirement.status == .blocked)
    #expect(contractRequirement.artifactIntegrity.first?.status == .verified)
    #expect(contractRequirement.diagnosticCodes.contains("release-envelope-contract-audit-not-passed"))
    #expect(contractRequirement.diagnosticCodes.contains("release-envelope-contract-audit-failed-contracts"))
    #expect(contractRequirement.diagnosticCodes.contains("release-envelope-contract-audit-contract-failed"))
    #expect(contractRequirement.diagnosticCodes.contains("release-envelope-contract-audit-contract-required-paths-missing"))
    #expect(envelope.diagnostics.contains {
        $0.code == "release-envelope-corpus-dashboard-not-passed"
    })
    #expect(envelope.diagnostics.contains {
        $0.code == "release-envelope-contract-audit-not-passed"
    })
}

@Test func collectReleaseEvidenceCLIWritesArtifactsConsumedByReleaseEnvelope() async throws {
    let root = try makeTemporaryRoot("agent-release-evidence-cli")
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
    let dashboardURL = root.appending(path: "signoff-dashboard.json")
    let contractURL = root.appending(path: "contract-report.json")
    try Data("""
    {
      "schemaVersion": 1,
      "status": "passed",
      "history": {
        "status": "passed",
        "previousEntryCount": 2,
        "maxTotalDurationRegression": 1.5,
        "appended": true,
        "domains": [
          {
            "domain": "drc",
            "status": "passed",
            "previousQualifiedEntryCount": 2,
            "current": {
              "status": "passed",
              "qualified": true,
              "caseCount": 3,
              "passRate": 1.0,
              "totalDurationSeconds": 1.2,
              "coverageTagCount": 4
            },
            "baseline": {
              "medianPassRate": 1.0,
              "medianTotalDurationSeconds": 1.0,
              "maxAllowedTotalDurationSeconds": 1.5
            },
            "durationRegressionRatio": 1.2,
            "failures": []
          }
        ],
        "promotion": {
          "status": "passed",
          "failures": []
        },
        "failures": []
      },
      "retainedSignoffSuite": {
        "status": "passed"
      }
    }
    """.utf8).write(to: dashboardURL, options: .atomic)
    try Data("""
    {
      "schemaVersion": 1,
      "status": "passed",
      "contractCount": 1,
      "failedContractCount": 0,
      "contracts": [
        {
          "id": "xcircuite.run-manifest.v2",
          "owner": "XcircuiteWorkspace",
          "status": "passed",
          "expectedVersion": 1,
          "observedVersion": 1,
          "requiredPathCount": 9,
          "failures": []
        }
      ]
    }
    """.utf8).write(to: contractURL, options: .atomic)

    let result = try await collectTestReleaseEvidence(
        runID: "run-1",
        projectRoot: root,
        signoffDashboardURL: dashboardURL,
        contractReportURL: contractURL
    )

    #expect(result.artifacts.map(\.artifactID).contains("qualification-corpus-history"))
    #expect(result.artifacts.map(\.artifactID).contains("qualification-performance-envelope"))
    #expect(result.artifacts.map(\.artifactID).contains("qualification-contract-audit"))
    #expect(!result.corpusHistory.collectedAt.isEmpty)
    #expect(result.corpusHistory.previousEntryCount == 2)
    #expect(result.performanceEnvelope.domains.first?.durationRegressionRatio == 1.2)
    #expect(result.contractAudit.failedContractCount == 0)

    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )
    let envelope = try await makeTestReleaseEnvelopeBuilder(projectRoot: root).buildReleaseEnvelope(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    ).envelope

    #expect(envelope.requirements.contains {
        $0.requirementID == "retained-corpus-history" && $0.status == .passed
    })
    #expect(envelope.requirements.contains {
        $0.requirementID == "performance-envelope" && $0.status == .passed
    })
    #expect(envelope.requirements.contains {
        $0.requirementID == "contract-audit" && $0.status == .passed
    })
    #expect(!envelope.diagnostics.contains {
        $0.code == "release-envelope-corpus-history-missing"
    })
}

@Test func collectReleaseEvidenceRejectsMalformedReleaseEvidenceSources() async throws {
    let root = try makeTemporaryRoot("agent-release-evidence-source-validation")
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
    let dashboardURL = root.appending(path: "signoff-dashboard.json")
    let contractURL = root.appending(path: "contract-report.json")
    try Data("""
    {
      "schemaVersion": 1,
      "status": "passed",
      "history": {
        "status": "passed",
        "previousEntryCount": 1,
        "maxTotalDurationRegression": 1.5,
        "domains": [],
        "promotion": {"status": "passed", "failures": []},
        "failures": []
      },
      "retainedSignoffSuite": {"status": "passed"}
    }
    """.utf8).write(to: dashboardURL, options: .atomic)
    try Data("""
    {
      "schemaVersion": 1,
      "status": "passed",
      "contractCount": 1,
      "failedContractCount": 0,
      "contracts": [
        {
          "id": "xcircuite.run-manifest.v2",
          "owner": "XcircuiteWorkspace",
          "status": "passed"
        }
      ]
    }
    """.utf8).write(to: contractURL, options: .atomic)

    await #expect(throws: FlowRunReleaseEvidenceCollectionError.self) {
        _ = try await collectTestReleaseEvidence(
            runID: "run-1",
            projectRoot: root,
            signoffDashboardURL: dashboardURL,
            contractReportURL: contractURL
        )
    }
}

@Test func releaseEnvelopeBlocksFailedPerformanceBudgetPromotion() async throws {
    let root = try makeTemporaryRoot("agent-release-performance-budget-failed")
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
    let dashboardURL = root.appending(path: "signoff-dashboard.json")
    let contractURL = root.appending(path: "contract-report.json")
    try Data("""
    {
      "schemaVersion": 1,
      "status": "failed",
      "history": {
        "status": "failed",
        "previousEntryCount": 2,
        "maxTotalDurationRegression": 1.5,
        "appended": true,
        "domains": [
          {
            "domain": "drc",
            "status": "failed",
            "previousQualifiedEntryCount": 2,
            "current": {
              "status": "passed",
              "qualified": true,
              "caseCount": 3,
              "passRate": 1.0,
              "totalDurationSeconds": 2.2,
              "coverageTagCount": 4
            },
            "baseline": {
              "medianPassRate": 1.0,
              "medianTotalDurationSeconds": 1.0,
              "maxAllowedTotalDurationSeconds": 1.5
            },
            "durationRegressionRatio": 2.2,
            "failures": [
              {"code": "duration_regression"}
            ]
          }
        ],
        "promotion": {
          "status": "failed",
          "failures": [
            {"code": "duration_regression"}
          ]
        },
        "failures": [
          {"code": "duration_regression"}
        ]
      },
      "retainedSignoffSuite": {
        "status": "passed"
      }
    }
    """.utf8).write(to: dashboardURL, options: .atomic)
    try Data("""
    {
      "schemaVersion": 1,
      "status": "passed",
      "contractCount": 1,
      "failedContractCount": 0,
      "contracts": []
    }
    """.utf8).write(to: contractURL, options: .atomic)

    _ = try await collectTestReleaseEvidence(
        runID: "run-1",
        projectRoot: root,
        signoffDashboardURL: dashboardURL,
        contractReportURL: contractURL
    )
    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    let envelope = try await makeTestReleaseEnvelopeBuilder(projectRoot: root).buildReleaseEnvelope(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    ).envelope

    #expect(envelope.status == .blocked)
    #expect(envelope.requirements.contains {
        $0.requirementID == "performance-envelope"
            && $0.status == .blocked
            && $0.diagnosticCodes.contains("release-envelope-performance-promotion-failed")
            && $0.diagnosticCodes.contains("release-envelope-performance-promotion-failures")
            && $0.diagnosticCodes.contains("release-envelope-performance-duration-budget-exceeded")
            && $0.diagnosticCodes.contains("release-envelope-performance-regression-budget-exceeded")
    })
    #expect(envelope.diagnostics.contains {
        $0.code == "release-envelope-performance-promotion-failed"
    })
}

	@Test func releaseEnvelopeBlocksStaleCollectedReleaseEvidence() async throws {
	    let root = try makeTemporaryRoot("agent-release-evidence-stale")
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
    let dashboardURL = root.appending(path: "signoff-dashboard.json")
    let contractURL = root.appending(path: "contract-report.json")
    try Data("""
    {
      "schemaVersion": 1,
      "status": "passed",
      "history": {
        "status": "passed",
        "previousEntryCount": 1,
        "maxTotalDurationRegression": 2.0,
        "domains": [],
        "promotion": {"status": "passed", "failures": []},
        "failures": []
      },
      "retainedSignoffSuite": {"status": "passed"}
    }
    """.utf8).write(to: dashboardURL, options: .atomic)
    try Data("""
    {
      "schemaVersion": 1,
      "status": "passed",
      "contractCount": 1,
      "failedContractCount": 0,
      "contracts": []
    }
    """.utf8).write(to: contractURL, options: .atomic)

    let oldDate = Date(timeIntervalSince1970: 0)
    _ = try await collectTestReleaseEvidence(
        runID: "run-1",
        projectRoot: root,
        signoffDashboardURL: dashboardURL,
        contractReportURL: contractURL,
        currentDate: oldDate
    )
    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root)
    )

    let currentDate = oldDate.addingTimeInterval(31 * 24 * 60 * 60)
    let envelope = try await makeTestReleaseEnvelopeBuilder(
        projectRoot: root,
        currentDate: currentDate
    ).buildReleaseEnvelope(
        runID: "run-1",
        workspaceID: try testWorkspaceID(for: root),
        maxEvidenceAgeDays: 30
    ).envelope

    #expect(envelope.status == .blocked)
    #expect(envelope.requirements.contains {
        $0.requirementID == "retained-corpus-history"
            && $0.status == .blocked
            && $0.diagnosticCodes.contains("release-envelope-corpus-history-stale")
    })
	    #expect(envelope.diagnostics.contains {
	        $0.code == "release-envelope-corpus-history-stale"
	    })
	}

	@Test func releaseEnvelopeBlocksFutureCollectedReleaseEvidence() async throws {
	    let root = try makeTemporaryRoot("agent-release-evidence-future")
	    defer { removeTemporaryRoot(root) }
	    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
	    let corpusPath = ".xcircuite/runs/run-1/qualification/corpus-history.json"
	    let futureDate = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 60 * 60))
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
	            TestArtifactReference(
	                artifactID: "qualification-corpus-history",
	                path: corpusPath,
	                kind: .report,
	                format: .json
	            ),
	        ],
	        artifactPayloads: [
	            summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8),
	            corpusPath: Data("""
	            {
	              "schemaVersion": 1,
	              "runID": "run-1",
	              "collectedAt": "\(futureDate)",
	              "sourceDashboardPath": "signoff-dashboard.json",
	              "sourceDashboardSHA256": "sha256",
	              "dashboardStatus": "passed",
	              "historyStatus": "passed",
	              "previousEntryCount": 1,
	              "appended": true,
	              "retainedSignoffSuiteStatus": "passed",
	              "domains": [
	                {
	                  "domain": "drc",
	                  "status": "passed",
	                  "previousQualifiedEntryCount": 1,
	                  "currentStatus": "passed",
	                  "qualified": true,
	                  "caseCount": 1,
	                  "passRate": 1.0,
	                  "totalDurationSeconds": 1.0,
	                  "coverageTagCount": 1,
	                  "failureCount": 0
	                }
	              ],
	              "diagnostics": []
	            }
	            """.utf8),
	        ]
	    )
	    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
	        runID: "run-1",
	        workspaceID: try testWorkspaceID(for: root)
	    )

	    let envelope = try await makeTestReleaseEnvelopeBuilder(
	        projectRoot: root,
	        currentDate: Date(timeIntervalSince1970: 0)
	    ).buildReleaseEnvelope(
	        runID: "run-1",
	        workspaceID: try testWorkspaceID(for: root),
	        maxEvidenceAgeDays: 30
	    ).envelope

	    #expect(envelope.status == .blocked)
	    #expect(envelope.requirements.contains {
	        $0.requirementID == "retained-corpus-history"
	            && $0.status == .blocked
	            && $0.diagnosticCodes.contains("release-envelope-corpus-history-collected-at-in-future")
	    })
	}

	@Test func releaseEnvelopeBlocksRetainedArtifactReferenceMismatch() async throws {
	    let root = try makeTemporaryRoot("agent-release-artifact-reference-mismatch")
	    defer { removeTemporaryRoot(root) }
	    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
	    let corpusPath = ".xcircuite/runs/run-1/qualification/corpus-history.json"
	    let collectedAt = ISO8601DateFormatter().string(from: Date())
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
	            TestArtifactReference(
	                artifactID: "wrong-corpus-history",
	                path: corpusPath,
	                kind: .report,
	                format: .json
	            ),
	        ],
	        artifactPayloads: [
	            summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8),
	            corpusPath: Data("""
	            {
	              "schemaVersion": 1,
	              "runID": "run-1",
	              "collectedAt": "\(collectedAt)",
	              "dashboardStatus": "passed",
	              "historyStatus": "passed",
	              "previousEntryCount": 1,
	              "appended": true,
	              "retainedSignoffSuiteStatus": "passed",
	              "domains": [
	                {
	                  "domain": "drc",
	                  "status": "passed",
	                  "qualified": true,
	                  "caseCount": 1,
	                  "passRate": 1.0,
	                  "coverageTagCount": 1,
	                  "failureCount": 0
	                }
	              ],
	              "diagnostics": []
	            }
	            """.utf8),
	        ]
	    )
	    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
	        runID: "run-1",
	        workspaceID: try testWorkspaceID(for: root)
	    )

	    let envelope = try await makeTestReleaseEnvelopeBuilder(projectRoot: root).buildReleaseEnvelope(
	        runID: "run-1",
	        workspaceID: try testWorkspaceID(for: root)
	    ).envelope

	    let corpusRequirement = try #require(envelope.requirements.first {
	        $0.requirementID == "retained-corpus-history"
	    })
	    #expect(envelope.status == .blocked)
	    #expect(corpusRequirement.status == .blocked)
	    #expect(corpusRequirement.diagnosticCodes.contains("release-envelope-corpus-history-reference-mismatch"))
	    #expect(corpusRequirement.artifactIDs.contains("qualification-corpus-history"))
	    #expect(corpusRequirement.artifactIDs.contains("wrong-corpus-history"))
	}

	@Test func releaseEnvelopeBlocksFractionalEvidenceCounts() async throws {
	    let root = try makeTemporaryRoot("agent-release-fractional-counts")
	    defer { removeTemporaryRoot(root) }
	    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
	    let corpusPath = ".xcircuite/runs/run-1/qualification/corpus-history.json"
	    let performancePath = ".xcircuite/runs/run-1/qualification/performance-envelope.json"
	    let contractPath = ".xcircuite/runs/run-1/qualification/contract-audit.json"
	    let collectedAt = ISO8601DateFormatter().string(from: Date())
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
	            TestArtifactReference(
	                artifactID: "qualification-corpus-history",
	                path: corpusPath,
	                kind: .report,
	                format: .json
	            ),
	            TestArtifactReference(
	                artifactID: "qualification-performance-envelope",
	                path: performancePath,
	                kind: .report,
	                format: .json
	            ),
	            TestArtifactReference(
	                artifactID: "qualification-contract-audit",
	                path: contractPath,
	                kind: .report,
	                format: .json
	            ),
	        ],
	        artifactPayloads: [
	            summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8),
	            corpusPath: Data("""
	            {
	              "schemaVersion": 1,
	              "runID": "run-1",
	              "collectedAt": "\(collectedAt)",
	              "dashboardStatus": "passed",
	              "historyStatus": "passed",
	              "previousEntryCount": 1.5,
	              "appended": true,
	              "retainedSignoffSuiteStatus": "passed",
	              "domains": [
	                {
	                  "domain": "drc",
	                  "status": "passed",
	                  "qualified": true,
	                  "caseCount": 3.2,
	                  "passRate": 1.0,
	                  "coverageTagCount": 4.4,
	                  "failureCount": 0.5
	                }
	              ],
	              "diagnostics": []
	            }
	            """.utf8),
	            performancePath: Data("""
	            {
	              "schemaVersion": 1,
	              "runID": "run-1",
	              "collectedAt": "\(collectedAt)",
	              "historyStatus": "passed",
	              "maxTotalDurationRegression": 1.5,
	              "domains": [
	                {
	                  "domain": "drc",
	                  "status": "passed",
	                  "currentTotalDurationSeconds": 1.2,
	                  "maxAllowedTotalDurationSeconds": 1.5,
	                  "durationRegressionRatio": 1.2,
	                  "failureCount": 0.5
	                }
	              ],
	              "promotionStatus": "passed",
	              "promotionFailureCount": 0.5,
	              "diagnostics": []
	            }
	            """.utf8),
	            contractPath: Data("""
	            {
	              "schemaVersion": 1,
	              "runID": "run-1",
	              "collectedAt": "\(collectedAt)",
	              "status": "passed",
	              "contractCount": 1.5,
	              "failedContractCount": 0.5,
	              "contracts": [
	                {
	                  "contractID": "xcircuite.run-manifest.v2",
	                  "status": "passed",
	                  "requiredPathCount": 9.5,
	                  "failureCount": 0.5
	                }
	              ],
	              "diagnostics": []
	            }
	            """.utf8),
	        ]
	    )
	    _ = try await makeTestDecisionPacketBuilder(projectRoot: root).buildDecisionPacket(
	        runID: "run-1",
	        workspaceID: try testWorkspaceID(for: root)
	    )

	    let envelope = try await makeTestReleaseEnvelopeBuilder(projectRoot: root).buildReleaseEnvelope(
	        runID: "run-1",
	        workspaceID: try testWorkspaceID(for: root)
	    ).envelope

	    #expect(envelope.status == .blocked)
	    #expect(envelope.requirements.contains {
	        $0.requirementID == "retained-corpus-history"
	            && $0.diagnosticCodes.contains("release-envelope-corpus-previous-history-count-invalid")
	            && $0.diagnosticCodes.contains("release-envelope-corpus-domain-case-count-invalid")
	            && $0.diagnosticCodes.contains("release-envelope-corpus-domain-coverage-count-invalid")
	            && $0.diagnosticCodes.contains("release-envelope-corpus-domain-failure-count-invalid")
	    })
	    #expect(envelope.requirements.contains {
	        $0.requirementID == "performance-envelope"
	            && $0.diagnosticCodes.contains("release-envelope-performance-promotion-failure-count-invalid")
	            && $0.diagnosticCodes.contains("release-envelope-performance-domain-failure-count-invalid")
	    })
	    #expect(envelope.requirements.contains {
	        $0.requirementID == "contract-audit"
	            && $0.diagnosticCodes.contains("release-envelope-contract-audit-contract-count-invalid")
	            && $0.diagnosticCodes.contains("release-envelope-contract-audit-failed-contract-count-invalid")
	            && $0.diagnosticCodes.contains("release-envelope-contract-audit-contract-required-path-count-invalid")
	            && $0.diagnosticCodes.contains("release-envelope-contract-audit-contract-failure-count-invalid")
	    })
	}

	}

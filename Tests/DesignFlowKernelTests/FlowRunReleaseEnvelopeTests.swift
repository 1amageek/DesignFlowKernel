import DesignFlowKernel
import DesignFlowCLISupport
import Foundation
import Testing
import ToolQualification
import XcircuitePackage

extension FlowRunLedgerSummaryTests {
@Test func releaseEnvelopeBuilderPersistsBlockedEnvelopeAndRegistersRunArtifact() async throws {
    let root = try makeTemporaryRoot("agent-release-envelope")
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

    let result = try DefaultFlowRunReleaseEnvelopeBuilder().buildReleaseEnvelope(
        runID: "run-1",
        projectRoot: root
    )

    #expect(result.artifact.artifactID == "qualification-release-envelope")
    #expect(result.artifact.path == ".xcircuite/runs/run-1/qualification/release-envelope.json")
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

    let manifest = try XcircuitePackageStore().readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
    )
    #expect(manifest.artifacts.contains {
        $0.artifactID == "qualification-release-envelope"
            && $0.path == ".xcircuite/runs/run-1/qualification/release-envelope.json"
    })
}

@Test func buildReleaseEnvelopeProcessExitIsNonZeroWhenEnvelopeBlocks() async throws {
    let root = try makeTemporaryRoot("agent-release-envelope-process-exit")
    defer { removeTemporaryRoot(root) }
    try await createBlockedApprovalRun(root: root, runID: "run-1")
    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    let result = try await DesignFlowCLICommand.runProcess(
        arguments: [
            "build-release-envelope",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
        ]
    )
    let data = try #require(result.output.data(using: .utf8))
    let build = try JSONDecoder().decode(FlowRunReleaseEnvelopeBuildResult.self, from: data)

    #expect(build.envelope.status == .blocked)
    #expect(result.exitCode == 2)
}

@Test func buildReleaseEnvelopeCLIEmitsVerifiedReleaseEvidenceJSON() async throws {
    let root = try makeTemporaryRoot("agent-release-envelope-cli")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let corpusPath = ".xcircuite/runs/run-1/qualification/corpus-history.json"
    let performancePath = ".xcircuite/runs/run-1/qualification/performance-envelope.json"
    let migrationPath = ".xcircuite/runs/run-1/qualification/migration-audit.json"
    let collectedAt = ISO8601DateFormatter().string(from: Date())
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
            XcircuiteFileReference(
                artifactID: "qualification-corpus-history",
                path: corpusPath,
                kind: .report,
                format: .json
            ),
            XcircuiteFileReference(
                artifactID: "qualification-performance-envelope",
                path: performancePath,
                kind: .report,
                format: .json
            ),
            XcircuiteFileReference(
                artifactID: "qualification-migration-audit",
                path: migrationPath,
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
            migrationPath: Data("""
            {
              "schemaVersion": 1,
              "runID": "run-1",
              "collectedAt": "\(collectedAt)",
              "sourceReportPath": "migration-report.json",
              "sourceReportSHA256": "sha256",
              "status": "passed",
              "contractCount": 1,
              "failedContractCount": 0,
              "contracts": [
                {
                  "contractID": "xcircuite.run-manifest.v1",
                  "owner": "XcircuitePackage",
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
        ]
    )
    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    let json = try DesignFlowCLICommand.run(
        arguments: [
            "build-release-envelope",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(FlowRunReleaseEnvelopeBuildResult.self, from: data)

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
        $0.requirementID == "migration-audit"
            && $0.status == .passed
            && $0.artifactIntegrity.first?.status == .verified
    })
    #expect(result.envelope.replayCommands.contains {
        $0.commandID == "build-release-envelope" && $0.readiness == .ready
    })
}

@Test func releaseEnvelopeBlocksFailedCorpusHistoryAndMigrationAuditContent() async throws {
    let root = try makeTemporaryRoot("agent-release-corpus-migration-content-failed")
    defer { removeTemporaryRoot(root) }
    let summaryPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
    let corpusPath = ".xcircuite/runs/run-1/qualification/corpus-history.json"
    let performancePath = ".xcircuite/runs/run-1/qualification/performance-envelope.json"
    let migrationPath = ".xcircuite/runs/run-1/qualification/migration-audit.json"
    let collectedAt = ISO8601DateFormatter().string(from: Date())
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
            XcircuiteFileReference(
                artifactID: "qualification-corpus-history",
                path: corpusPath,
                kind: .report,
                format: .json
            ),
            XcircuiteFileReference(
                artifactID: "qualification-performance-envelope",
                path: performancePath,
                kind: .report,
                format: .json
            ),
            XcircuiteFileReference(
                artifactID: "qualification-migration-audit",
                path: migrationPath,
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
            migrationPath: Data("""
            {
              "schemaVersion": 1,
              "runID": "run-1",
              "collectedAt": "\(collectedAt)",
              "sourceReportPath": "migration-report.json",
              "sourceReportSHA256": "sha256",
              "status": "failed",
              "contractCount": 1,
              "failedContractCount": 1,
              "contracts": [
                {
                  "contractID": "xcircuite.run-manifest.v1",
                  "owner": "XcircuitePackage",
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
                  "code": "release-migration-audit-not-passed",
                  "message": "Versioned contract fixture report status is not passed."
                }
              ]
            }
            """.utf8),
        ]
    )
    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    let envelope = try DefaultFlowRunReleaseEnvelopeBuilder().buildReleaseEnvelope(
        runID: "run-1",
        projectRoot: root
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

    let migrationRequirement = try #require(envelope.requirements.first {
        $0.requirementID == "migration-audit"
    })
    #expect(migrationRequirement.status == .blocked)
    #expect(migrationRequirement.artifactIntegrity.first?.status == .verified)
    #expect(migrationRequirement.diagnosticCodes.contains("release-envelope-migration-audit-not-passed"))
    #expect(migrationRequirement.diagnosticCodes.contains("release-envelope-migration-audit-failed-contracts"))
    #expect(migrationRequirement.diagnosticCodes.contains("release-envelope-migration-audit-contract-failed"))
    #expect(migrationRequirement.diagnosticCodes.contains("release-envelope-migration-audit-contract-required-paths-missing"))
    #expect(envelope.diagnostics.contains {
        $0.code == "release-envelope-corpus-dashboard-not-passed"
    })
    #expect(envelope.diagnostics.contains {
        $0.code == "release-envelope-migration-audit-not-passed"
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
            XcircuiteFileReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8)]
    )
    let dashboardURL = root.appending(path: "signoff-dashboard.json")
    let migrationURL = root.appending(path: "migration-report.json")
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
          "id": "xcircuite.run-manifest.v1",
          "owner": "XcircuitePackage",
          "status": "passed",
          "expectedVersion": 1,
          "observedVersion": 1,
          "requiredPathCount": 9,
          "failures": []
        }
      ]
    }
    """.utf8).write(to: migrationURL, options: .atomic)

    let json = try DesignFlowCLICommand.run(
        arguments: [
            "collect-release-evidence",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
            "--signoff-dashboard",
            dashboardURL.path(percentEncoded: false),
            "--migration-report",
            migrationURL.path(percentEncoded: false),
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(FlowRunReleaseEvidenceCollectionResult.self, from: data)

    #expect(result.artifacts.map(\.artifactID).contains("qualification-corpus-history"))
    #expect(result.artifacts.map(\.artifactID).contains("qualification-performance-envelope"))
    #expect(result.artifacts.map(\.artifactID).contains("qualification-migration-audit"))
    #expect(!result.corpusHistory.collectedAt.isEmpty)
    #expect(result.corpusHistory.previousEntryCount == 2)
    #expect(result.performanceEnvelope.domains.first?.durationRegressionRatio == 1.2)
    #expect(result.migrationAudit.failedContractCount == 0)

    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )
    let envelope = try DefaultFlowRunReleaseEnvelopeBuilder().buildReleaseEnvelope(
        runID: "run-1",
        projectRoot: root
    ).envelope

    #expect(envelope.requirements.contains {
        $0.requirementID == "retained-corpus-history" && $0.status == .passed
    })
    #expect(envelope.requirements.contains {
        $0.requirementID == "performance-envelope" && $0.status == .passed
    })
    #expect(envelope.requirements.contains {
        $0.requirementID == "migration-audit" && $0.status == .passed
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
            XcircuiteFileReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8)]
    )
    let dashboardURL = root.appending(path: "signoff-dashboard.json")
    let migrationURL = root.appending(path: "migration-report.json")
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
      "contractCount": 1,
      "failedContractCount": 0,
      "contracts": []
    }
    """.utf8).write(to: migrationURL, options: .atomic)

    #expect(throws: FlowRunReleaseEvidenceCollectionError.self) {
        _ = try DefaultFlowRunReleaseEvidenceCollector().collectReleaseEvidence(
            runID: "run-1",
            projectRoot: root,
            signoffDashboardPath: dashboardURL,
            migrationReportPath: migrationURL
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
            XcircuiteFileReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8)]
    )
    let dashboardURL = root.appending(path: "signoff-dashboard.json")
    let migrationURL = root.appending(path: "migration-report.json")
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
    """.utf8).write(to: migrationURL, options: .atomic)

    _ = try DefaultFlowRunReleaseEvidenceCollector().collectReleaseEvidence(
        runID: "run-1",
        projectRoot: root,
        signoffDashboardPath: dashboardURL,
        migrationReportPath: migrationURL
    )
    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    let envelope = try DefaultFlowRunReleaseEnvelopeBuilder().buildReleaseEnvelope(
        runID: "run-1",
        projectRoot: root
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
            XcircuiteFileReference(
                artifactID: "drc-summary",
                path: summaryPath,
                kind: .report,
                format: .json
            ),
        ],
        artifactPayloads: [summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8)]
    )
    let dashboardURL = root.appending(path: "signoff-dashboard.json")
    let migrationURL = root.appending(path: "migration-report.json")
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
    """.utf8).write(to: migrationURL, options: .atomic)

    let oldDate = Date(timeIntervalSince1970: 0)
    _ = try DefaultFlowRunReleaseEvidenceCollector(currentDate: oldDate).collectReleaseEvidence(
        runID: "run-1",
        projectRoot: root,
        signoffDashboardPath: dashboardURL,
        migrationReportPath: migrationURL
    )
    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
        runID: "run-1",
        projectRoot: root
    )

    let currentDate = oldDate.addingTimeInterval(31 * 24 * 60 * 60)
    let envelope = try DefaultFlowRunReleaseEnvelopeBuilder(currentDate: currentDate).buildReleaseEnvelope(
        runID: "run-1",
        projectRoot: root,
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
	            XcircuiteFileReference(
	                artifactID: "drc-summary",
	                path: summaryPath,
	                kind: .report,
	                format: .json
	            ),
	            XcircuiteFileReference(
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
	    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
	        runID: "run-1",
	        projectRoot: root
	    )

	    let envelope = try DefaultFlowRunReleaseEnvelopeBuilder(
	        currentDate: Date(timeIntervalSince1970: 0)
	    ).buildReleaseEnvelope(
	        runID: "run-1",
	        projectRoot: root,
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
	            XcircuiteFileReference(
	                artifactID: "drc-summary",
	                path: summaryPath,
	                kind: .report,
	                format: .json
	            ),
	            XcircuiteFileReference(
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
	    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
	        runID: "run-1",
	        projectRoot: root
	    )

	    let envelope = try DefaultFlowRunReleaseEnvelopeBuilder().buildReleaseEnvelope(
	        runID: "run-1",
	        projectRoot: root
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
	    let migrationPath = ".xcircuite/runs/run-1/qualification/migration-audit.json"
	    let collectedAt = ISO8601DateFormatter().string(from: Date())
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
	            XcircuiteFileReference(
	                artifactID: "qualification-corpus-history",
	                path: corpusPath,
	                kind: .report,
	                format: .json
	            ),
	            XcircuiteFileReference(
	                artifactID: "qualification-performance-envelope",
	                path: performancePath,
	                kind: .report,
	                format: .json
	            ),
	            XcircuiteFileReference(
	                artifactID: "qualification-migration-audit",
	                path: migrationPath,
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
	            migrationPath: Data("""
	            {
	              "schemaVersion": 1,
	              "runID": "run-1",
	              "collectedAt": "\(collectedAt)",
	              "status": "passed",
	              "contractCount": 1.5,
	              "failedContractCount": 0.5,
	              "contracts": [
	                {
	                  "contractID": "xcircuite.run-manifest.v1",
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
	    _ = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
	        runID: "run-1",
	        projectRoot: root
	    )

	    let envelope = try DefaultFlowRunReleaseEnvelopeBuilder().buildReleaseEnvelope(
	        runID: "run-1",
	        projectRoot: root
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
	        $0.requirementID == "migration-audit"
	            && $0.diagnosticCodes.contains("release-envelope-migration-audit-contract-count-invalid")
	            && $0.diagnosticCodes.contains("release-envelope-migration-audit-failed-contract-count-invalid")
	            && $0.diagnosticCodes.contains("release-envelope-migration-audit-contract-required-path-count-invalid")
	            && $0.diagnosticCodes.contains("release-envelope-migration-audit-contract-failure-count-invalid")
	    })
	}

	}

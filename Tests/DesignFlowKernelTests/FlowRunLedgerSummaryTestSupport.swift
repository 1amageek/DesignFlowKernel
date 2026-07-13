import DesignFlowKernel
import DesignFlowCLISupport
import Foundation
import Testing
import ToolQualification
import XcircuitePackage

extension FlowRunLedgerSummaryTests {
func drcRequirement(requiredEvidenceKinds: [ToolEvidenceKind] = []) -> ToolTrustRequirement {
    ToolTrustRequirement(
        kind: .drc,
        operationID: "run-drc",
        minimumLevel: .corpusChecked,
        requiredInputFormats: [.oasis],
        requiredOutputFormats: [.json],
        requiredEvidenceKinds: requiredEvidenceKinds
    )
}

func drcDescriptor() -> ToolDescriptor {
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
        trustProfile: ToolTrustProfile(level: .corpusChecked),
        environment: ToolEnvironment(platform: "macOS")
    )
}

func qualifiedCorpusEvidence(_ evidenceID: String = "corpus-1") -> ToolEvidence {
    ToolEvidence(
        evidenceID: evidenceID,
        kind: .corpus,
        qualification: ToolEvidenceQualificationSummary(
            qualified: true,
            policyID: "unit-test-policy",
            observedMetrics: ["passRate": 1],
            observedCounts: ["caseCount": 1]
        )
    )
}

func createArtifactCoverageFailureRun(root: URL, runID: String) async throws {
    let summaryPath = ".xcircuite/runs/\(runID)/stages/001-drc/raw/drc-summary.json"
    let payload = Data(#"{"artifactID":"drc-summary"}"#.utf8)
    _ = try await DefaultFlowOrchestrator().run(
        request: FlowOperationRequest(
            projectRoot: root,
            runID: runID,
            intent: "Run DRC artifact coverage",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC"),
            ]
        ),
        toolRegistry: ToolRegistry(),
        healthResults: [:],
        executors: [
            SummaryStageExecutor(
                stageID: "001-drc",
                toolID: "native-drc",
                status: .failed,
                gates: [
                    FlowGateResult(
                        gateID: "drc-artifacts",
                        status: .failed,
                        diagnostics: [
                            FlowDiagnostic(
                                severity: .error,
                                code: "ARTIFACT_MANIFEST_OUTPUT_NOT_INDEXED",
                                message: "The DRC artifact manifest output is not indexed by the flow result."
                            ),
                        ]
                    ),
                ],
                artifacts: [
                    XcircuiteFileReference(
                        artifactID: "drc-summary",
                        path: summaryPath,
                        kind: .report,
                        format: .json
                    ),
                ],
                artifactPayloads: [summaryPath: payload]
            ),
        ]
    )
}

func makeTemporaryRoot(_ name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "FlowRunLedgerSummaryTests-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

func removeTemporaryRoot(_ root: URL) {
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

func createBlockedApprovalRun(
    root: URL,
    runID: String,
    stageID: String = "001-drc",
    artifacts: [XcircuiteFileReference] = [],
    artifactPayloads: [String: Data] = [:]
) async throws {
    let descriptor = drcDescriptor()
    _ = try await DefaultFlowOrchestrator().run(
        request: FlowOperationRequest(
            projectRoot: root,
            runID: runID,
            intent: "Run DRC with human review",
            stages: [
                FlowStageDefinition(
                    stageID: stageID,
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
            SummaryStageExecutor(
                stageID: stageID,
                toolID: "native-drc",
                status: .succeeded,
                artifacts: artifacts,
                artifactPayloads: artifactPayloads
            ),
        ]
    )
}

func writeRunArtifact(
    _ payload: Data,
    path: String,
    artifactID: String,
    root: URL,
    runID: String
) throws {
    try FileManager.default.createDirectory(
        at: root.appending(path: path).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try payload.write(to: root.appending(path: path), options: .atomic)
    let reference = try XcircuitePackageStore().fileReference(
        forProjectRelativePath: path,
        artifactID: artifactID,
        kind: .other,
        format: .json,
        inProjectAt: root,
        producedByRunID: runID
    )
    try XcircuitePackageStore().upsertRunArtifact(reference, runID: runID, inProjectAt: root)
}
}

struct SummaryStageExecutor: FlowStageExecutor {
    let stageID: String
    let toolID: String
    let status: FlowStageStatus
    var gates: [FlowGateResult] = []
    var artifacts: [XcircuiteFileReference] = []
    var artifactPayloads: [String: Data] = [:]

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        var resolvedArtifacts = artifacts
        for index in resolvedArtifacts.indices {
            let path = resolvedArtifacts[index].path
            guard let payload = artifactPayloads[path] else {
                continue
            }
            let url = context.projectRoot.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try payload.write(to: url, options: .atomic)
            resolvedArtifacts[index].sha256 = XcircuiteHasher().sha256(data: payload)
            resolvedArtifacts[index].byteCount = Int64(payload.count)
        }

        return FlowStageResult(
            stageID: stage.stageID,
            status: status,
            gates: gates,
            artifacts: resolvedArtifacts
        )
    }
}

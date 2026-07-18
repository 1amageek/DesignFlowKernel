import DesignFlowKernel
import CircuiteFoundation
import Foundation
import Testing
import ToolQualification
import DesignFlowKernel

extension FlowRunLedgerSummaryTests {
func drcRequirement(requiredEvidenceKinds: [ToolEvidenceKind] = []) -> ToolTrustRequirement {
    ToolTrustRequirement(
        kind: .drc,
        operationID: "run-drc",
        minimumLevel: .smokeChecked,
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
        trustProfile: ToolTrustProfile(level: .smokeChecked),
        environment: ToolEnvironment(platform: "macOS")
    )
}

func createArtifactCoverageFailureRun(root: URL, runID: String) async throws {
    let summaryPath = ".xcircuite/runs/\(runID)/stages/001-drc/raw/drc-summary.json"
    let payload = Data(#"{"artifactID":"drc-summary"}"#.utf8)
    _ = try await makeTestOrchestrator(projectRoot: root).run(
        request: FlowOperationRequest(
            workspaceID: try testWorkspaceID(for: root),
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
                    TestArtifactReference(
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
    artifacts: [TestArtifactReference] = [],
    artifactPayloads: [String: Data] = [:]
) async throws {
    let qualification = try await TestToolQualificationFixtures.qualificationRecord(
        for: drcDescriptor(),
        projectRoot: root
    )
    let descriptor = qualification.descriptor
    _ = try await makeTestOrchestrator(projectRoot: root).run(
        request: FlowOperationRequest(
            workspaceID: try testWorkspaceID(for: root),
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
        toolRegistry: try ToolRegistry(descriptors: [descriptor]),
        healthResults: [
            descriptor.toolID: qualification.health,
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
) async throws {
    try FileManager.default.createDirectory(
        at: root.appending(path: path).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try payload.write(to: root.appending(path: path), options: .atomic)
    let reference = try await TestFlowInfrastructure.bound(to: root).fileReference(
        forProjectRelativePath: path,
        artifactID: artifactID,
        kind: .other,
        format: .json,
        inProjectAt: root,
        producerRunID: runID
    )
    try await TestFlowInfrastructure.bound(to: root).upsertRunArtifact(reference, runID: runID, inProjectAt: root)
}
}

struct SummaryStageExecutor: FlowStageExecutor {
    let stageID: String
    let toolID: String
    let status: FlowStageStatus
    var gates: [FlowGateResult] = []
    var artifacts: [TestArtifactReference] = []
    var artifactPayloads: [String: Data] = [:]

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        var resolvedArtifacts: [ArtifactReference] = []
        for artifact in artifacts {
            let reference = try foundationReference(from: artifact)
            guard let payload = artifactPayloads[artifact.path] else {
                resolvedArtifacts.append(reference)
                continue
            }
            resolvedArtifacts.append(
                try await context.infrastructure.persistArtifact(
                    content: payload,
                    id: reference.id,
                    locator: reference.locator,
                    runID: context.runID,
                    mode: .replaceable
                )
            )
        }

        return FlowStageResult(
            stageID: stage.stageID,
            status: status,
            gates: gates,
            artifacts: resolvedArtifacts
        )
    }

    private func foundationReference(
        from fixture: TestArtifactReference
    ) throws -> ArtifactReference {
        ArtifactReference(
            id: try fixture.artifactID.map { try ArtifactID(rawValue: $0) },
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: fixture.path),
                role: fixture.role,
                kind: try ArtifactKind(rawValue: fixture.kind.rawValue),
                format: try ArtifactFormat(rawValue: fixture.format.rawValue.lowercased())
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: fixture.sha256 ?? String(repeating: "0", count: 64)
            ),
            byteCount: UInt64(fixture.byteCount ?? 0)
        )
    }
}

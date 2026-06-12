import Foundation
import DesignFlowKernel
import Testing
import ToolQualification
import XcircuitePackage

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

        let result = try await DefaultFlowOrchestrator().run(
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

        let runManifest = try XcircuitePackageStore().readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(runManifest.runID == "run-1")
        #expect(runManifest.status == .succeeded)
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

        let result = try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "pure-swift-drc", status: .succeeded),
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

        let result = try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(descriptors: [descriptor]),
            healthResults: [
                descriptor.toolID: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            ],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "pure-swift-drc", status: .succeeded),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(result.stages[0].status == .succeeded)
    }

    @Test func stageBlocksWhenSelectedToolDoesNotMatchExecutorTool() async throws {
        let root = try makeTemporaryRoot("tool-mismatch")
        defer { removeTemporaryRoot(root) }

        let descriptor = drcDescriptor()
        let result = try await DefaultFlowOrchestrator().run(
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
                descriptor.toolID: ToolHealthCheckResult(toolID: descriptor.toolID, status: .passed),
            ],
            executors: [
                StubStageExecutor(stageID: "001-drc", toolID: "other-drc", status: .succeeded),
            ]
        )

        #expect(result.status == .blocked)
        #expect(result.stages[0].diagnostics.contains { $0.code == "EXECUTOR_TOOL_MISMATCH" })
        #expect(fileExists(".xcircuite/runs/run-1/stages/001-drc/result.json", in: root))
    }

    @Test func executorFailurePersistsFailedStageAndRunManifest() async throws {
        let root = try makeTemporaryRoot("executor-failure")
        defer { removeTemporaryRoot(root) }

        let result = try await DefaultFlowOrchestrator().run(
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

        let runManifest = try XcircuitePackageStore().readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(runManifest.status == .failed)
    }

    @Test func missingExecutorThrowsBeforeWritingRunArtifacts() async throws {
        let root = try makeTemporaryRoot("missing-executor")
        defer { removeTemporaryRoot(root) }

        await #expect(throws: FlowExecutionError.self) {
            try await DefaultFlowOrchestrator().run(
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
            try await DefaultFlowOrchestrator().run(
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

        await #expect(throws: XcircuitePackageError.self) {
            try await DefaultFlowOrchestrator().run(
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
        #expect(!fileExists(".xcircuite/escape", in: root))
    }

    private func drcRequirement() -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .corpusChecked,
            requiredInputFormats: [.oasis],
            requiredOutputFormats: [.json]
        )
    }

    private func drcDescriptor() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "pure-swift-drc",
            displayName: "Pure Swift DRC",
            kind: .drc,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-drc",
                    inputFormats: [.oasis],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(level: .productionEligible),
            environment: ToolEnvironment(platform: "macOS")
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
        defer { try? FileManager.default.removeItem(at: root) }

        let request = FlowOperationRequest(
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
        let blocked = try await DefaultFlowOrchestrator().run(
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
        try XcircuitePackageStore().writeApproval(
            XcircuiteApprovalRecord(
                runID: "run-approve",
                stageID: "001-drc",
                verdict: .approved,
                reviewer: "reviewer-1",
                note: "looks clean"
            ),
            inProjectAt: root
        )
        let resumed = try await DefaultFlowOrchestrator().run(
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
        defer { try? FileManager.default.removeItem(at: root) }

        let request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-reject",
            intent: "Approval flow",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
            ]
        )
        try XcircuitePackageStore().createPackage(at: root)
        _ = try XcircuitePackageStore().createRunDirectory(for: "run-reject", inProjectAt: root)
        try XcircuitePackageStore().writeApproval(
            XcircuiteApprovalRecord(
                runID: "run-reject",
                stageID: "001-drc",
                verdict: .rejected,
                reviewer: "reviewer-1",
                note: "needs a wider rail"
            ),
            inProjectAt: root
        )

        let result = try await DefaultFlowOrchestrator().run(
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
}

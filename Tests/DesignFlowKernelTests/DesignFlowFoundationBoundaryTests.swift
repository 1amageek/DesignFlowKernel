import CircuiteFoundation
import DesignFlowKernel
import Foundation
import Testing
import DesignFlowKernel

@Suite("Design-flow Foundation boundary")
struct DesignFlowFoundationBoundaryTests {
    @Test("flow evidence preserves opaque artifact identity and canonical format")
    func preservesOpaqueArtifactIdentity() throws {
        let artifact = XcircuiteFileReference(
            artifactID: "rtl-netlist",
            path: "runs/run-1/design.sv",
            kind: .rtl,
            format: .systemVerilog,
            sha256: String(repeating: "a", count: 64),
            byteCount: 32
        )
        let result = FlowRunResult(
            runID: "run-1",
            status: .succeeded,
            runDirectory: URL(filePath: "/tmp/run-1"),
            stages: [FlowStageResult(
                stageID: "rtl",
                status: .succeeded,
                artifacts: [artifact]
            )]
        )
        let timestamp = Date(timeIntervalSince1970: 10)
        let provenance = try ExecutionProvenance(
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "design-flow",
                version: "1"
            ),
            startedAt: timestamp,
            completedAt: timestamp.addingTimeInterval(1)
        )

        let evidence = try DesignFlowFoundationEvidence(
            result: result,
            provenance: provenance
        )

        #expect(evidence.artifacts.count == 1)
        #expect(evidence.artifacts[0].id.rawValue == "rtl-netlist")
        #expect(evidence.artifacts[0].locator.kind.rawValue == "flow.rtl")
        #expect(evidence.artifacts[0].locator.format == .systemVerilog)

        let decoded = try JSONDecoder().decode(
            DesignFlowFoundationEvidence.self,
            from: JSONEncoder().encode(evidence)
        )
        #expect(decoded == evidence)
    }

    @Test("flow evidence derives a deterministic identity when legacy ID is absent")
    func derivesDeterministicIdentityForLegacyReference() throws {
        let artifact = XcircuiteFileReference(
            path: "runs/run-1/report.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "b", count: 64),
            byteCount: 16
        )
        let result = FlowRunResult(
            runID: "run-1",
            status: .succeeded,
            runDirectory: URL(filePath: "/tmp/run-1"),
            stages: [FlowStageResult(
                stageID: "report",
                status: .succeeded,
                artifacts: [artifact]
            )]
        )
        let timestamp = Date(timeIntervalSince1970: 10)
        let provenance = try ExecutionProvenance(
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "design-flow",
                version: "1"
            ),
            startedAt: timestamp,
            completedAt: timestamp.addingTimeInterval(1)
        )

        let first = try DesignFlowFoundationEvidence(
            result: result,
            provenance: provenance
        )
        let second = try DesignFlowFoundationEvidence(
            result: result,
            provenance: provenance
        )

        #expect(first.artifacts[0].id == second.artifacts[0].id)
        #expect(!first.artifacts[0].id.rawValue.isEmpty)
    }
}

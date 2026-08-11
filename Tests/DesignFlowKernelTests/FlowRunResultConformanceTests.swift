import CircuiteFoundation
import Foundation
import Testing
import DesignFlowKernel

@Suite("Flow result Foundation conformance")
struct FlowRunResultConformanceTests {
    @Test("workspace identity is validated and Codable")
    func validatesWorkspaceIdentity() throws {
        let identifier = try FlowWorkspaceID(rawValue: "workspace-1")
        let decoded = try JSONDecoder().decode(
            FlowWorkspaceID.self,
            from: JSONEncoder().encode(identifier)
        )
        #expect(decoded == identifier)
        #expect(throws: FlowWorkspaceIDError.invalidValue("../workspace")) {
            try FlowWorkspaceID(rawValue: "../workspace")
        }
    }

    @Test("flow result preserves canonical artifacts and provenance")
    func preservesOpaqueArtifactIdentity() throws {
        let artifact = try ArtifactReference(
            digest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "a", count: 64)
            ),
            byteCount: 32,
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: .rtl,
                format: .systemVerilog
            )
        )
        let binding = try FlowArtifactBinding(
            logicalID: "rtl-netlist",
            reference: artifact,
            availability: .local(
                artifactID: artifact.id,
                rootID: ArtifactRootID(rawValue: "test-workspace"),
                relativePath: FlowArtifactPath.relative("runs/run-1/design.sv")
            )
        )
        let timestamp = Date(timeIntervalSince1970: 10)
        let provenance = try ExecutionProvenance(
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "design-flow-kernel",
                version: "1"
            ),
            startedAt: timestamp,
            completedAt: timestamp.addingTimeInterval(1)
        )

        let result = try FlowRunResult(
            runID: "run-1",
            status: .succeeded,
            stages: [FlowStageResult(
                stageID: "rtl",
                status: .succeeded,
                artifacts: [binding]
            )],
            provenance: provenance
        )

        #expect(result.artifacts.count == 1)
        #expect(result.artifacts[0].id == artifact.id)
        #expect(result.artifacts[0].descriptor.kind == ArtifactKind.rtl)
        #expect(result.artifacts[0].descriptor.format == ArtifactFormat.systemVerilog)
        #expect(result.evidence.provenance == provenance)

        let decoded = try JSONDecoder().decode(
            FlowRunResult.self,
            from: JSONEncoder().encode(result)
        )
        #expect(decoded == result)
    }

    @Test("flow evidence derives a deterministic identity when ID is absent")
    func derivesDeterministicIdentityWithoutExplicitID() throws {
        let artifact = try ArtifactReference(
            digest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "b", count: 64)
            ),
            byteCount: 16,
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: .report,
                format: .json
            )
        )
        let binding = try FlowArtifactBinding(
            logicalID: "report",
            reference: artifact,
            availability: .local(
                artifactID: artifact.id,
                rootID: ArtifactRootID(rawValue: "test-workspace"),
                relativePath: FlowArtifactPath.relative("runs/run-1/report.json")
            )
        )
        let timestamp = Date(timeIntervalSince1970: 10)
        let provenance = try ExecutionProvenance(
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "design-flow-kernel",
                version: "1"
            ),
            startedAt: timestamp,
            completedAt: timestamp.addingTimeInterval(1)
        )

        let first = try FlowRunResult(
            runID: "run-1",
            status: .succeeded,
            stages: [FlowStageResult(
                stageID: "report",
                status: .succeeded,
                artifacts: [binding]
            )],
            provenance: provenance
        )
        let second = try FlowRunResult(
            runID: "run-1",
            status: .succeeded,
            stages: [FlowStageResult(
                stageID: "report",
                status: .succeeded,
                artifacts: [binding]
            )],
            provenance: provenance
        )

        #expect(first.artifacts[0].id == second.artifacts[0].id)
        #expect(!first.artifacts[0].id.description.isEmpty)
    }

    @Test("decoding rejects evidence that diverges from stage artifacts")
    func rejectsDivergentEvidence() throws {
        let timestamp = Date(timeIntervalSince1970: 10)
        let provenance = try ExecutionProvenance(
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "design-flow-kernel",
                version: "1"
            ),
            startedAt: timestamp,
            completedAt: timestamp.addingTimeInterval(1)
        )
        let result = try FlowRunResult(
            runID: "run-1",
            status: .succeeded,
            stages: [],
            provenance: provenance
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
        )
        var evidence = try #require(object["evidence"] as? [String: Any])
        let artifact = try ArtifactReference(
            digest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "a", count: 64)
            ),
            byteCount: 1,
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: .report,
                format: .json
            )
        )
        let artifactObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(artifact)) as? [String: Any]
        )
        evidence["artifacts"] = [artifactObject]
        object["evidence"] = evidence
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: FlowRunResultValidationError.artifactEvidenceMismatch) {
            try JSONDecoder().decode(FlowRunResult.self, from: data)
        }
    }
}

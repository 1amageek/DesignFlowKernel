import CircuiteFoundation
import DesignFlowKernel
import Foundation
import Testing
import DesignFlowKernel

@Suite("Design-flow Foundation boundary")
struct DesignFlowFoundationBoundaryTests {
    @Test("review action requests decode legacy artifact references")
    func decodesLegacyReviewActionArtifacts() throws {
        let digest = String(repeating: "a", count: 64)
        let legacyPayload: [String: Any] = [
            "actionID": "waive-width",
            "runID": "run-1",
            "stageID": "001-drc",
            "actor": ["kind": "human", "identifier": "reviewer-1"],
            "decisionKind": "review.waiverDecision",
            "decision": "waived",
            "targetID": "drc-width-1",
            "targetPath": ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json",
            "reason": "Known fixture exception.",
            "status": "succeeded",
            "inputs": [[
                "artifactID": "drc-input",
                "path": ".xcircuite/runs/run-1/stages/001-drc/input.json",
                "kind": "report",
                "format": "JSON",
                "sha256": digest,
                "byteCount": 12,
            ]],
            "outputs": [],
            "diagnostics": [],
            "metadata": [:],
            "createdAt": 0.0,
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload)
        let request = try JSONDecoder().decode(
            XcircuiteRunReviewDecisionActionRequest.self,
            from: legacyData
        )

        #expect(request.inputs.count == 1)
        #expect(request.inputs[0].id.rawValue == "drc-input")
        #expect(request.inputs[0].locator.role == .legacyUnspecified)
        #expect(request.inputs[0].locator.format == .json)

        let encodedData = try JSONEncoder().encode(request)
        let encodedObject = try #require(
            JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        )
        let encodedInputs = try #require(encodedObject["inputs"] as? [[String: Any]])
        #expect(encodedInputs[0]["locator"] != nil)
        #expect(encodedInputs[0]["path"] == nil)
    }

    @Test("release envelope results decode legacy artifact references")
    func decodesLegacyReleaseEnvelopeArtifact() throws {
        let artifact = ArtifactReference(
            id: try ArtifactID(rawValue: "qualification-release-envelope"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/runs/run-1/qualification/release-envelope.json"
                ),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "b", count: 64)
            ),
            byteCount: 8
        )
        let envelope = FlowRunReleaseEnvelope(
            envelopeID: "release-envelope-run-1",
            runID: "run-1",
            status: .blocked,
            decisionPacketValidation: FlowRunDecisionPacketValidationResult(
                runID: "run-1",
                packetPath: ".xcircuite/runs/run-1/review/decision-packet.json",
                status: .blocked
            ),
            requirements: []
        )
        let canonical = FlowRunReleaseEnvelopeBuildResult(
            envelope: envelope,
            artifact: artifact
        )
        var object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(canonical)
            ) as? [String: Any]
        )
        object["artifact"] = [
            "artifactID": "qualification-release-envelope",
            "path": ".xcircuite/runs/run-1/qualification/release-envelope.json",
            "kind": "report",
            "format": "JSON",
            "sha256": String(repeating: "b", count: 64),
            "byteCount": 8,
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(
            FlowRunReleaseEnvelopeBuildResult.self,
            from: legacyData
        )

        #expect(decoded.artifact.id.rawValue == artifact.id.rawValue)
        #expect(decoded.artifact.locator.role == .legacyUnspecified)
        #expect(decoded.artifact.locator.location.value == artifact.locator.location.value)
    }


    @Test("execution storage publishes Foundation artifact references")
    func executionStoragePublishesFoundationArtifactReferences() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appending(path: "design-flow-foundation-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: projectRoot)
            } catch {
                assertionFailure("Failed to remove test project: \(error.localizedDescription)")
            }
        }

        let storage: any FlowExecutionStorage = XcircuitePackageStore()
        try storage.ensureRunDirectory(for: "run-1", inProjectAt: projectRoot)
        let artifactURL = projectRoot
            .appending(path: XcircuitePackage.directoryName)
            .appending(path: "runs/run-1/result.json")
        try FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("result".utf8).write(to: artifactURL, options: .atomic)

        let reference = try storage.makeArtifactReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/run-1/result.json",
            artifactID: "run-result",
            role: .output,
            kind: .report,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: "run-1",
            verifiedByRunID: nil
        )
        #expect(reference.id.rawValue == "run-result")
        #expect(reference.locator.role == .output)
        #expect(reference.locator.kind == .report)
        #expect(reference.locator.format == .json)
        #expect(reference.byteCount == 6)

        try storage.registerArtifact(reference, runID: "run-1", inProjectAt: projectRoot)
        let manifest = try storage.loadRunManifest(runID: "run-1", inProjectAt: projectRoot)
        #expect(manifest.artifacts.contains { $0.artifactID == "run-result" })
    }

    @Test("flow evidence preserves opaque artifact identity and canonical format")
    func preservesOpaqueArtifactIdentity() throws {
        let artifact = ArtifactReference(
            id: try ArtifactID(rawValue: "rtl-netlist"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "runs/run-1/design.sv"),
                role: .output,
                kind: .rtl,
                format: .systemVerilog
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "a", count: 64)
            ),
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
        let artifact = ArtifactReference(
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "runs/run-1/report.json"),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "b", count: 64)
            ),
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

import CircuiteFoundation
import Foundation
import Testing
@testable import DesignFlowKernel

@Suite("Flow waiver and release evidence")
struct FlowRunWaiverAndReleaseEvidenceTests {
    @Test
    func rejectsWaiverWithoutReviewReason() async throws {
        let ledger = try makeLedger(runID: "run-waiver")
        let store = WaiverLedgerStore(ledger: ledger)
        let recorder = DefaultFlowGateApprovalRecorder(
            loader: store,
            inspector: store,
            ledgerPersistence: store
        )

        await #expect(throws: FlowGateApprovalError.waiverReasonRequired) {
            try await recorder.recordApproval(
                FlowGateApprovalRequest(
                    workspaceID: try testWorkspaceID(for: URL(filePath: "/tmp/project")),
                    runID: "run-waiver",
                    stageID: "layout",
                    verdict: .waived,
                    reviewer: "operator",
                    note: ""
                )
            )
        }
    }

    @Test
    func generatesFailClosedReleaseEvidenceArtifact() async throws {
        let root = URL(filePath: "/tmp/project")
        let ledger = try makeLedger(runID: "run-release")
        let store = ReleaseEvidenceStore(ledger: ledger)
        let validator = PassingDecisionPacketValidator(runID: "run-release")
        let builder = DefaultFlowRunReleaseEnvelopeBuilder(
            decisionPacketValidator: validator,
            loader: store,
            persistence: store,
            currentDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let result = try await builder.buildReleaseEnvelope(
            runID: "run-release",
            workspaceID: try testWorkspaceID(for: root)
        )

        #expect(result.envelope.status == .blocked)
        #expect(!result.envelope.requirements.isEmpty)
        #expect(result.envelope.requirements.contains { $0.required && $0.status == .blocked })
        #expect(result.artifact.id.rawValue == DefaultFlowRunReleaseEnvelopeBuilder.artifactID)
        #expect(await store.persistedArtifactCount == 1)
    }

    private func makeLedger(runID: String) throws -> FlowRunLedger {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return FlowRunLedger(
            runID: runID,
            runManifest: try FlowRunManifest(
                runID: runID,
                status: .blocked,
                actor: FlowRunActor(kind: .system, identifier: "test"),
                createdAt: now,
                updatedAt: now,
                startedAt: now,
                finishedAt: now
            ),
            stages: []
        )
    }
}

private actor WaiverLedgerStore: FlowRunLedgerPersisting, FlowRunLedgerInspecting {
    private var ledger: FlowRunLedger

    init(ledger: FlowRunLedger) {
        self.ledger = ledger
    }

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        ledger
    }

    func saveRunLedger(_ ledger: FlowRunLedger) async throws {
        self.ledger = ledger
    }

    func inspectRun(runID: String, workspaceID: FlowWorkspaceID) async throws -> FlowRunLedgerSummary {
        FlowRunLedgerSummary(runID: runID, status: ledger.runManifest.status)
    }
}

private struct PassingDecisionPacketValidator: FlowRunDecisionPacketValidating {
    let runID: String

    func validateDecisionPacket(
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws -> FlowRunDecisionPacketValidationResult {
        FlowRunDecisionPacketValidationResult(
            runID: runID,
            packetPath: "runs/\(runID)/review/decision-packet.json",
            status: .passed
        )
    }
}

private actor ReleaseEvidenceStore: FlowRunLedgerLoading, FlowArtifactPersisting {
    private let ledger: FlowRunLedger
    private(set) var persistedArtifactCount = 0

    init(ledger: FlowRunLedger) {
        self.ledger = ledger
    }

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        ledger
    }

    func persistArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference {
        persistedArtifactCount += 1
        return ArtifactReference(
            id: id,
            locator: locator,
            digest: try SHA256ContentDigester().digest(data: content),
            byteCount: UInt64(content.count)
        )
    }

    func loadArtifactContent(
        for reference: ArtifactReference
    ) async throws -> Data {
        throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
            path: reference.locator.location.value,
            reason: "missing retained release evidence"
        )
    }

    func loadArtifactContent(
        at locator: ArtifactLocator,
    ) async throws -> Data? {
        nil
    }

    func artifactExists(
        at locator: ArtifactLocator,
    ) async throws -> Bool {
        false
    }
}

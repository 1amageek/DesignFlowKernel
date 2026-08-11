import CircuiteFoundation
import CircuiteFoundationCrypto
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
            approvalPersistence: store
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
        #expect(result.artifact.logicalID == DefaultFlowRunReleaseEnvelopeBuilder.artifactID)
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

private actor WaiverLedgerStore: FlowRunApprovalArtifactPersisting, FlowRunLedgerInspecting {
    private var ledger: FlowRunLedger
    private var contentByAvailability: [ArtifactAvailability: Data] = [:]

    init(ledger: FlowRunLedger) {
        self.ledger = ledger
    }

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        ledger
    }

    func saveRunLedger(_ ledger: FlowRunLedger) async throws -> FlowRunLedger {
        self.ledger = ledger
        return ledger
    }

    func createRunLedger(_ ledger: FlowRunLedger) async throws -> FlowRunLedger {
        throw FlowRunLedgerPersistenceError.runAlreadyExists(runID: ledger.runID)
    }

    func appendActionArtifact(
        content: Data,
        logicalID: String,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor,
        producer: ProducerIdentity?,
        action: FlowRunActionRecord
    ) async throws -> FlowRunLedger {
        let binding = try makeBinding(
            content: content,
            logicalID: logicalID,
            relativePath: relativePath,
            descriptor: descriptor,
            producer: producer
        )
        guard action.outputs == [binding.reference] else {
            throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                runID: action.runID,
                path: binding.availabilityDescription
            )
        }
        ledger.actions.append(action)
        ledger.artifacts.append(binding)
        contentByAvailability[binding.availability] = content
        return ledger
    }

    func appendApprovalArtifact(
        content: Data,
        logicalID: String,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor,
        producer: ProducerIdentity?,
        approval: FlowApprovalRecord,
        action: FlowRunActionRecord
    ) async throws -> FlowRunLedger {
        let binding = try makeBinding(
            content: content,
            logicalID: logicalID,
            relativePath: relativePath,
            descriptor: descriptor,
            producer: producer
        )
        guard action.outputs == [binding.reference] else {
            throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                runID: action.runID,
                path: binding.availabilityDescription
            )
        }
        ledger.approvals.append(approval)
        ledger.actions.append(action)
        ledger.artifacts.append(binding)
        contentByAvailability[binding.availability] = content
        return ledger
    }

    func loadArtifactContent(for binding: FlowArtifactBinding) async throws -> Data {
        guard let content = contentByAvailability[binding.availability] else {
            throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                path: binding.availabilityDescription,
                reason: "test store has no artifact content"
            )
        }
        return content
    }

    private func makeBinding(
        content: Data,
        logicalID: String,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor,
        producer: ProducerIdentity?
    ) throws -> FlowArtifactBinding {
        let reference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: content),
            byteCount: UInt64(content.count),
            descriptor: descriptor
        )
        return try FlowArtifactBinding(
            logicalID: logicalID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(rawValue: "waiver-test"),
                relativePath: relativePath
            ),
            producer: producer
        )
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
    private var contentByPath: [ArtifactRelativePath: Data] = [:]

    init(ledger: FlowRunLedger) {
        self.ledger = ledger
    }

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        ledger
    }

    func persistArtifact(
        content: Data,
        logicalID: String,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor,
        runID: String,
        producer: ProducerIdentity?,
        mode: FlowArtifactPersistenceMode
    ) async throws -> FlowArtifactBinding {
        persistedArtifactCount += 1
        contentByPath[relativePath] = content
        let reference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: content),
            byteCount: UInt64(content.count),
            descriptor: descriptor
        )
        return try FlowArtifactBinding(
            logicalID: logicalID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(rawValue: "release-test"),
                relativePath: relativePath
            ),
            producer: producer
        )
    }

    func loadArtifactContent(
        for binding: FlowArtifactBinding
    ) async throws -> Data {
        guard case .local(_, _, let relativePath) = binding.availability,
              let content = contentByPath[relativePath] else {
            throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                path: binding.availabilityDescription,
                reason: "missing retained release evidence"
            )
        }
        return content
    }

    func loadArtifactContent(
        at relativePath: ArtifactRelativePath
    ) async throws -> Data? {
        contentByPath[relativePath]
    }

    func artifactExists(
        at relativePath: ArtifactRelativePath
    ) async throws -> Bool {
        contentByPath[relativePath] != nil
    }
}

import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation
@testable import DesignFlowKernel

func testWorkspaceID(for root: URL) throws -> FlowWorkspaceID {
    let digest = try SHA256ContentDigester()
        .digest(data: Data(root.standardizedFileURL.path(percentEncoded: false).utf8))
        .hexadecimalValue
    return try FlowWorkspaceID(
        rawValue: "workspace-\(digest.prefix(24))"
    )
}

actor TestFlowInfrastructure: FlowRunInfrastructure, FlowRunLedgerPersisting, FlowRunReviewLedgerLoading, FlowRunApprovalArtifactPersisting {
    private static let registry = TestFlowInfrastructureRegistry()

    static func bound(to projectRoot: URL) async -> TestFlowInfrastructure {
        await registry.infrastructure(for: projectRoot)
    }

    let projectRoot: URL

    private var ledgers: [String: FlowRunLedger] = [:]
    private var approvals: [String: FlowApprovalRecord] = [:]
    private var progressEvents: [String: [FlowRunProgressEvent]] = [:]
    private var cancellations: [String: FlowRunCancellationRequest] = [:]
    private var envelopeRecords: [String: [FlowArtifactEnvelopeRecord]] = [:]
    private var bindingsByContentID: [ArtifactID: FlowArtifactBinding] = [:]

    init(projectRoot: URL) {
        self.projectRoot = Self.canonicalRoot(projectRoot)
    }

    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        guard let binding = bindingsByContentID[reference.id] else {
            throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                path: reference.id.description,
                reason: "artifact availability is not registered"
            )
        }
        return try await loadArtifactContent(for: binding)
    }

    func registerArtifactBinding(_ binding: FlowArtifactBinding) {
        bindingsByContentID[binding.reference.id] = binding
    }

    func prepareRun(
        runID: String,
        requireNew: Bool
    ) async throws {
        let key = runKey(runID: runID, projectRoot: projectRoot)
        if requireNew, ledgers[key] != nil {
            throw FlowExecutionError.duplicateRunID(runID)
        }
        let directory = projectRoot.appending(path: ".xcircuite/runs/\(runID)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        let key = runKey(runID: runID, projectRoot: projectRoot)
        guard var ledger = ledgers[key] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        }
        let runDirectory = projectRoot.appending(path: ".xcircuite/runs/\(runID)")
        let planURL = runDirectory.appending(path: "plan.json")
        if FileManager.default.fileExists(atPath: planURL.path(percentEncoded: false)) {
            ledger.plan = try JSONDecoder().decode(FlowRunPlan.self, from: Data(contentsOf: planURL))
        }
        var projectedStages: [FlowStageResult] = []
        for stage in ledger.stages {
            let stageID = stage.stageID
            do {
                try FlowIdentifierValidator().validate(stageID, kind: .stageID)
            } catch {
                projectedStages.append(stage)
                continue
            }
            let resultURL = runDirectory.appending(path: "stages/\(stageID)/result.json")
            guard FileManager.default.fileExists(atPath: resultURL.path(percentEncoded: false)) else {
                throw FlowRunLedgerPersistenceError.storageFailed(
                    "persisted stage result is missing: \(stageID)"
                )
            }
            projectedStages.append(
                try JSONDecoder().decode(FlowStageResult.self, from: Data(contentsOf: resultURL))
            )
        }
        ledger.stages = projectedStages
        let isSyntheticFailureProjection = ledger.runManifest.status == .failed
            && ledger.stages.last.map { $0.stageID == "flow-setup" || $0.stageID == "flow-execution" } == true
        if let plan = ledger.plan, !isSyntheticFailureProjection {
            let plannedStageIDs = plan.stages.map(\.stageID)
            let resultStageIDs = ledger.stages.map(\.stageID)
            let hasInvalidStageID = resultStageIDs.contains { stageID in
                do {
                    try FlowIdentifierValidator().validate(stageID, kind: .stageID)
                    return false
                } catch {
                    return true
                }
            }
            guard hasInvalidStageID
                || Array(plannedStageIDs.prefix(resultStageIDs.count)) == resultStageIDs else {
                throw FlowRunLedgerPersistenceError.storageFailed(
                    "persisted stage results are not a prefix of the run plan"
                )
            }
        }
        ledgers[key] = ledger
        return ledger
    }

    func loadRunLedgerForReview(runID: String) async throws -> FlowRunLedger {
        try await loadRunLedger(runID: runID)
    }

    func saveRunLedger(_ proposed: FlowRunLedger) async throws -> FlowRunLedger {
        let key = runKey(runID: proposed.runID, projectRoot: projectRoot)
        if let current = ledgers[key], current != proposed {
            let expected = current.runManifest.revision + 1
            guard proposed.runManifest.revision == expected else {
                throw FlowRunLedgerPersistenceError.concurrentUpdate(
                    runID: proposed.runID,
                    expectedRevision: expected,
                    actualRevision: proposed.runManifest.revision
                )
            }
        } else if ledgers[key] == nil, proposed.runManifest.revision != 0 {
            throw FlowRunLedgerPersistenceError.concurrentUpdate(
                runID: proposed.runID,
                expectedRevision: 0,
                actualRevision: proposed.runManifest.revision
            )
        }
        ledgers[key] = proposed
        approvals = approvals.filter { !$0.key.hasPrefix("\(key)\u{001F}") }
        for approval in proposed.approvals {
            approvals[approvalKey(
                runID: proposed.runID,
                stageID: approval.stageID,
                projectRoot: projectRoot
            )] = approval
        }
        progressEvents[key] = proposed.progressEvents
        cancellations[key] = proposed.cancellationRequest
        try persistProjections(for: proposed)
        return proposed
    }

    func createRunLedger(_ proposed: FlowRunLedger) async throws -> FlowRunLedger {
        let key = runKey(runID: proposed.runID, projectRoot: projectRoot)
        guard ledgers[key] == nil else {
            throw FlowRunLedgerPersistenceError.runAlreadyExists(runID: proposed.runID)
        }
        return try await saveRunLedger(proposed)
    }

    func appendActionArtifact(
        content: Data,
        logicalID: String,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor,
        producer: ProducerIdentity?,
        action: FlowRunActionRecord
    ) async throws -> FlowRunLedger {
        try appendActionOwnedArtifact(
            content: content,
            logicalID: logicalID,
            relativePath: relativePath,
            descriptor: descriptor,
            producer: producer,
            approval: nil,
            action: action
        )
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
        try appendActionOwnedArtifact(
            content: content,
            logicalID: logicalID,
            relativePath: relativePath,
            descriptor: descriptor,
            producer: producer,
            approval: approval,
            action: action
        )
    }

    private func appendActionOwnedArtifact(
        content: Data,
        logicalID: String,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor,
        producer: ProducerIdentity?,
        approval: FlowApprovalRecord?,
        action: FlowRunActionRecord
    ) throws -> FlowRunLedger {
        let key = runKey(runID: action.runID, projectRoot: projectRoot)
        guard var ledger = ledgers[key] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: action.runID)
        }
        if ledger.actions.contains(where: { $0.actionID == action.actionID }) {
            throw FlowRunLedgerPersistenceError.duplicateActionID(
                runID: action.runID,
                actionID: action.actionID
            )
        }
        if let approval,
           ledger.approvals.contains(where: { $0.stageID == approval.stageID }) {
            throw FlowRunLedgerPersistenceError.duplicateApprovalID(
                runID: action.runID,
                approvalID: approval.stageID
            )
        }
        let binding = try makeBinding(
            content: content,
            logicalID: logicalID,
            relativePath: relativePath,
            descriptor: descriptor,
            producer: producer
        )
        guard action.runID == ledger.runID,
              action.outputs == [binding.reference] else {
            throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                runID: action.runID,
                path: binding.availabilityDescription
            )
        }
        if let approval {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let expectedContent = try encoder.encode(approval)
            let expectedPath = ".xcircuite/runs/\(approval.runID)/approvals/\(approval.stageID).json"
            guard approval.runID == action.runID,
                  action.stageID == approval.stageID,
                  binding.logicalID == "approval-\(approval.stageID)",
                  relativePath.stringValue == normalizedRelativePath(expectedPath),
                  binding.role == .output,
                  binding.kind == .report,
                  binding.format == .json,
                  action.inputs == [
                    approval.evidence.plan.reference,
                    approval.evidence.stageResult.reference,
                  ],
                  content == expectedContent else {
                throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                    runID: action.runID,
                    path: binding.availabilityDescription
                )
            }
        }
        let destination = try artifactURL(relativePath: relativePath)
        guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
            throw FlowRunLedgerPersistenceError.storageFailed(
                "immutable action artifact already exists: \(binding.availabilityDescription)"
            )
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        ledger.actions.append(action)
        if let approval {
            ledger.approvals.append(approval)
        }
        ledger.artifacts.removeAll { sameMaterializationPath($0, binding) }
        ledger.artifacts.append(binding)
        ledger.runManifest.artifacts = ledger.artifacts
        ledger.runManifest.revision += 1
        ledger.runManifest.updatedAt = max(Date(), ledger.runManifest.updatedAt)
        try content.write(to: destination, options: .atomic)
        bindingsByContentID[binding.reference.id] = binding
        ledgers[key] = ledger
        if let approval {
            approvals[approvalKey(
                runID: approval.runID,
                stageID: approval.stageID,
                projectRoot: projectRoot
            )] = approval
        }
        try persistManifestProjection(for: ledger)
        guard let stored = ledgers[key] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: action.runID)
        }
        return stored
    }

    func setRunStatus(_ status: FlowRunStatus, runID: String) throws {
        let key = runKey(runID: runID, projectRoot: projectRoot)
        guard var ledger = ledgers[key] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        }
        ledger.runManifest.status = status
        ledger.runManifest.revision += 1
        ledger.runManifest.updatedAt = Date()
        ledgers[key] = ledger
        try persistProjections(for: ledger)
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
        let url = try artifactURL(relativePath: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let destinationExists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false)
        )
        switch mode {
        case .createOnly where destinationExists:
            throw FlowRunLedgerPersistenceError.storageFailed(
                "artifact already exists: \(relativePath.stringValue)"
            )
        case .immutable where destinationExists:
            let existing = try Data(contentsOf: url)
            guard existing == content else {
                throw FlowRunLedgerPersistenceError.storageFailed(
                    "immutable artifact conflict: \(relativePath.stringValue)"
                )
            }
        case .appendOnly where destinationExists:
            let existing = try Data(contentsOf: url)
            guard content.starts(with: existing) else {
                throw FlowRunLedgerPersistenceError.storageFailed(
                    "append-only artifact conflict: \(relativePath.stringValue)"
                )
            }
            try content.write(to: url, options: .atomic)
        case .createOnly, .immutable, .replaceable, .appendOnly:
            try content.write(to: url, options: .atomic)
        }
        let binding = try makeBinding(
            content: content,
            logicalID: logicalID,
            relativePath: relativePath,
            descriptor: descriptor,
            producer: producer
        )
        bindingsByContentID[binding.reference.id] = binding
        let key = runKey(runID: runID, projectRoot: projectRoot)
        if var ledger = ledgers[key] {
            ledger.artifacts.removeAll { sameMaterializationPath($0, binding) }
            ledger.artifacts.append(binding)
            ledger.artifacts.sort { $0.availabilityDescription < $1.availabilityDescription }
            ledger.runManifest.artifacts = ledger.artifacts
            ledger.runManifest.revision += 1
            ledger.runManifest.updatedAt = Date()
            ledgers[key] = ledger
            try persistManifestProjection(for: ledger)
        }
        return binding
    }

    func persistRunControlArtifact(
        content: Data,
        logicalID: String,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor,
        runID: String,
        mode: FlowArtifactPersistenceMode
    ) async throws -> FlowArtifactBinding {
        try await persistArtifact(
            content: content,
            logicalID: logicalID,
            relativePath: relativePath,
            descriptor: descriptor,
            runID: runID,
            producer: nil,
            mode: mode
        )
    }

    func loadArtifactContent(
        for binding: FlowArtifactBinding
    ) async throws -> Data {
        let expectedRootID = try artifactRootID()
        guard case .local(_, let rootID, let relativePath) = binding.availability,
              rootID == expectedRootID else {
            throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                path: binding.availabilityDescription,
                reason: "test storage requires its local artifact root"
            )
        }
        let url = try artifactURL(relativePath: relativePath)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                path: binding.availabilityDescription,
                reason: error.localizedDescription
            )
        }
        let digest = try SHA256ContentDigester().digest(data: data)
        let reference = binding.reference
        guard digest == reference.digest, UInt64(data.count) == reference.byteCount else {
            throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                path: binding.availabilityDescription,
                reason: "digest or byte count mismatch"
            )
        }
        return data
    }

    func loadArtifactContent(
        at relativePath: ArtifactRelativePath
    ) async throws -> Data? {
        let url = try artifactURL(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    func artifactExists(at relativePath: ArtifactRelativePath) async throws -> Bool {
        return FileManager.default.fileExists(
            atPath: try artifactURL(relativePath: relativePath).path(percentEncoded: false)
        )
    }

    func verifyArtifact(_ binding: FlowArtifactBinding) async -> ArtifactIntegrity {
        do {
            _ = try await loadArtifactContent(for: binding)
            return ArtifactIntegrity()
        } catch let error as FlowRunLedgerPersistenceError {
            return ArtifactIntegrity(issues: [.unreadableFile(String(describing: error))])
        } catch {
            return ArtifactIntegrity(issues: [
                .unreadableFile(error.localizedDescription),
            ])
        }
    }

    func loadApproval(
        runID: String,
        stageID: String
    ) async throws -> FlowApprovalRecord? {
        approvals[approvalKey(runID: runID, stageID: stageID, projectRoot: projectRoot)]
    }

    func recordApproval(_ approval: FlowApprovalRecord, projectRoot: URL) {
        approvals[approvalKey(
            runID: approval.runID,
            stageID: approval.stageID,
            projectRoot: projectRoot
        )] = approval
    }

    func createWorkspace(at projectRoot: URL) throws {
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    }

    func ensureRunDirectory(for runID: String, inProjectAt projectRoot: URL) throws -> URL {
        let directory = projectRoot.appending(path: ".xcircuite/runs/\(runID)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = runKey(runID: runID, projectRoot: projectRoot)
        if ledgers[key] == nil {
            let now = Date()
            let ledger = FlowRunLedger(
                runID: runID,
                runManifest: try FlowRunManifest(
                    runID: runID,
                    status: .created,
                    actor: FlowRunActor(kind: .agent, identifier: "test-agent"),
                    intent: "test run",
                    createdAt: now,
                    updatedAt: now
                ),
                stages: []
            )
            ledgers[key] = ledger
            try persistProjections(for: ledger)
        }
        return directory
    }

    func createRunDirectory(
        for runID: String,
        actor: String,
        intent: String,
        inProjectAt projectRoot: URL
    ) throws -> URL {
        let directory = try ensureRunDirectory(for: runID, inProjectAt: projectRoot)
        if ledgers[runKey(runID: runID, projectRoot: projectRoot)] == nil {
            let now = Date()
            ledgers[runKey(runID: runID, projectRoot: projectRoot)] = FlowRunLedger(
                runID: runID,
                runManifest: try FlowRunManifest(
                    runID: runID,
                    status: .created,
                    actor: FlowRunActor(kind: .agent, identifier: actor),
                    intent: intent,
                    createdAt: now,
                    updatedAt: now
                ),
                stages: []
            )
        }
        return directory
    }

    func createRunDirectory(
        for runID: String,
        inProjectAt projectRoot: URL
    ) throws -> URL {
        try createRunDirectory(
            for: runID,
            actor: "test-agent",
            intent: "test run",
            inProjectAt: projectRoot
        )
    }

    func loadRunManifest(runID: String, inProjectAt projectRoot: URL) throws -> FlowRunManifest {
        guard let ledger = ledgers[runKey(runID: runID, projectRoot: projectRoot)] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        }
        return ledger.runManifest
    }

    func upsertRunArtifacts(
        _ bindings: [FlowArtifactBinding],
        runID: String,
        inProjectAt projectRoot: URL
    ) throws {
        for binding in bindings {
            try upsertRunArtifact(binding, runID: runID, inProjectAt: projectRoot)
        }
    }

    func appendReviewDecisionAction(
        _ request: FlowRunReviewDecisionRequest,
        inProjectAt projectRoot: URL
    ) throws {
        try appendRunAction(
            FlowRunActionRecord(
                actionID: request.actionID,
                runID: request.runID,
                stageID: request.stageID,
                actor: request.actor,
                actionKind: request.decisionKind.rawValue,
                status: request.status,
                inputs: request.inputs,
                outputs: request.outputs,
                diagnostics: request.diagnostics,
                context: FlowRunActionContext(
                    reviewDecision: FlowRunActionContext.ReviewDecision(
                        kind: request.decisionKind,
                        decision: request.decision,
                        targetID: request.targetID,
                        targetPath: request.targetPath,
                        reason: request.reason
                    )
                ),
                createdAt: request.createdAt
            ),
            inProjectAt: projectRoot
        )
    }

    func appendRunAction(_ action: FlowRunActionRecord, inProjectAt projectRoot: URL) throws {
        let key = runKey(runID: action.runID, projectRoot: projectRoot)
        guard var ledger = ledgers[key] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: action.runID)
        }
        ledger.actions.append(action)
        if let selection = try FlowRunSuggestedActionSelection(record: action) {
            ledger.suggestedActionSelections.append(selection)
        }
        ledger.runManifest.revision += 1
        ledger.runManifest.updatedAt = Date()
        ledgers[key] = ledger
        try persistProjections(for: ledger)
    }

    func loadRunActions(runID: String, inProjectAt projectRoot: URL) throws -> [FlowRunActionRecord] {
        guard let ledger = ledgers[runKey(runID: runID, projectRoot: projectRoot)] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        }
        return ledger.actions
    }

    func writeDesignDiff(_ diff: DesignDiff, inProjectAt projectRoot: URL) throws {
        let key = runKey(runID: diff.runID, projectRoot: projectRoot)
        guard var ledger = ledgers[key] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: diff.runID)
        }
        ledger.designDiff = diff
        ledger.runManifest.revision += 1
        ledger.runManifest.updatedAt = Date()
        ledgers[key] = ledger
        try persistProjections(for: ledger)
    }

    func writeApproval(_ approval: FlowApprovalRecord, inProjectAt projectRoot: URL) throws {
        let key = runKey(runID: approval.runID, projectRoot: projectRoot)
        guard var ledger = ledgers[key] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: approval.runID)
        }
        recordApproval(approval, projectRoot: projectRoot)
        ledger.approvals.removeAll { $0.stageID == approval.stageID }
        ledger.approvals.append(approval)
        ledger.runManifest.revision += 1
        ledger.runManifest.updatedAt = Date()
        ledgers[key] = ledger
        try persistProjections(for: ledger)
    }

    func loadApproval(
        runID: String,
        stageID: String,
        inProjectAt projectRoot: URL
    ) throws -> FlowApprovalRecord? {
        approvals[approvalKey(runID: runID, stageID: stageID, projectRoot: projectRoot)]
    }

    func writeJSON<Value: Encodable & Sendable>(
        _ value: Value,
        to url: URL,
        forProjectAt projectRoot: URL
    ) throws {
        guard Self.isContained(url, by: projectRoot) else {
            throw FlowRunLedgerPersistenceError.storageFailed(
                "test path outside project: candidate=\(Self.canonicalPath(url)) root=\(Self.canonicalPath(projectRoot))"
            )
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    func readJSON<Value: Decodable & Sendable>(_ type: Value.Type, from url: URL) throws -> Value {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    func fileReference(
        forProjectRelativePath path: String,
        artifactID: String? = nil,
        role: ArtifactRole = .output,
        kind: ArtifactKind,
        format: ArtifactFormat,
        inProjectAt projectRoot: URL,
        producerRunID: String? = nil
    ) throws -> FlowArtifactBinding {
        let data = try Data(contentsOf: projectRoot.appending(path: path))
        let binding = try makeBinding(
            content: data,
            logicalID: artifactID ?? "test-artifact",
            relativePath: try FlowArtifactPath.relative(normalizedRelativePath(path)),
            descriptor: ArtifactDescriptor(
                role: role,
                kind: kind,
                format: format
            ),
            producer: try producerRunID.map {
                try ProducerIdentity(kind: .engine, identifier: $0, version: "1")
            }
        )
        bindingsByContentID[binding.reference.id] = binding
        return binding
    }

    func upsertRunArtifact(
        _ binding: FlowArtifactBinding,
        runID: String,
        inProjectAt projectRoot: URL
    ) throws {
        let key = runKey(runID: runID, projectRoot: projectRoot)
        guard var ledger = ledgers[key] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        }
        ledger.artifacts.removeAll { sameMaterializationPath($0, binding) }
        ledger.artifacts.append(binding)
        ledger.runManifest.artifacts = ledger.artifacts
        ledger.runManifest.revision += 1
        ledger.runManifest.updatedAt = Date()
        ledgers[key] = ledger
        bindingsByContentID[binding.reference.id] = binding
    }

    func loadCancellationRequest(
        runID: String
    ) async throws -> FlowRunCancellationRequest? {
        cancellations[runKey(runID: runID, projectRoot: projectRoot)]
    }

    func appendProgressEvent(
        runID: String,
        kind: FlowRunProgressEventKind,
        stageID: String?,
        stageStatus: FlowStageStatus?,
        runStatus: FlowRunStatus?,
        message: String,
        createdAt: Date
    ) async throws -> FlowRunProgressEvent {
        _ = try ensureRunDirectory(for: runID, inProjectAt: projectRoot)
        let key = runKey(runID: runID, projectRoot: projectRoot)
        let sequence = (progressEvents[key, default: []].map(\.sequence).max() ?? 0) + 1
        let event = FlowRunProgressEvent(
            runID: runID,
            sequence: sequence,
            kind: kind,
            stageID: stageID,
            stageStatus: stageStatus,
            runStatus: runStatus,
            message: message,
            createdAt: createdAt
        )
        progressEvents[key, default: []].append(event)
        if var ledger = ledgers[key] {
            ledger.progressEvents = progressEvents[key, default: []]
            ledgers[key] = ledger
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var content = Data()
        for progressEvent in progressEvents[key, default: []] {
            content.append(try encoder.encode(progressEvent))
            content.append(Data("\n".utf8))
        }
        _ = try await persistArtifact(
            content: content,
            logicalID: "run-progress",
            relativePath: try FlowArtifactPath.relative("runs/\(event.runID)/progress.jsonl"),
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: .report,
                format: .text
            ),
            runID: event.runID,
            producer: nil,
            mode: .replaceable
        )
        return event
    }

    func loadProgressEvents(runID: String) async throws -> [FlowRunProgressEvent] {
        let key = runKey(runID: runID, projectRoot: projectRoot)
        guard progressEvents[key] != nil || ledgers[key] != nil else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        }
        return progressEvents[key, default: []]
    }

    func persistCancellationRequest(
        _ request: FlowRunCancellationRequest
    ) async throws -> FlowArtifactBinding {
        _ = try ensureRunDirectory(for: request.runID, inProjectAt: projectRoot)
        cancellations[runKey(runID: request.runID, projectRoot: projectRoot)] = request
        let key = runKey(runID: request.runID, projectRoot: projectRoot)
        if var ledger = ledgers[key] {
            ledger.cancellationRequest = request
            ledgers[key] = ledger
        }
        return try await persistJSON(
            request,
            id: "run-cancellation-request",
            path: ".xcircuite/runs/\(request.runID)/cancellation.json",
            runID: request.runID
        )
    }

    func runControlArtifacts(runID: String) async throws -> [FlowArtifactBinding] {
        let ledger: FlowRunLedger
        do {
            ledger = try await loadRunLedger(runID: runID)
        } catch FlowRunLedgerPersistenceError.resumeTargetNotFound {
            return []
        }
        return ledger.artifacts.filter {
            $0.logicalID == "run-progress" || $0.logicalID == "run-cancellation-request"
        }
    }

    func loadArtifactEnvelopeRecords(
        runID: String
    ) async throws -> [FlowArtifactEnvelopeRecord] {
        envelopeRecords[runKey(runID: runID, projectRoot: projectRoot), default: []]
    }

    func writeArtifactEnvelope(
        _ envelope: FlowArtifactEnvelope,
        runID: String,
        inProjectAt candidateRoot: URL
    ) async throws {
        guard Self.canonicalRoot(candidateRoot) == projectRoot else {
            throw FlowRunLedgerPersistenceError.storageFailed("test infrastructure root mismatch")
        }
        let binding = try await persistJSON(
            envelope,
            id: envelope.artifactID,
            path: ".xcircuite/runs/\(runID)/evidence/\(envelope.artifactID).json",
            runID: runID
        )
        let key = runKey(runID: runID, projectRoot: projectRoot)
        envelopeRecords[key, default: []].append(
            FlowArtifactEnvelopeRecord(envelope: envelope, persistedAt: Date())
        )
        guard var ledger = ledgers[key] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        }
        ledger.artifacts.removeAll { sameMaterializationPath($0, binding) }
        ledger.artifacts.append(binding)
        ledger.runManifest.artifacts = ledger.artifacts
        ledger.runManifest.revision += 1
        ledger.runManifest.updatedAt = Date()
        ledgers[key] = ledger
    }

    func persistCrossArtifactEvaluation(
        _ evaluation: FlowCrossArtifactEvaluation
    ) async throws -> FlowArtifactBinding {
        try await persistJSON(
            evaluation,
            id: "cross-artifact-evaluation",
            path: ".xcircuite/runs/\(evaluation.runID)/reports/cross-artifact-evaluation.json",
            runID: evaluation.runID
        )
    }

    func persistLoopIterationSummaries(
        _ iterations: [FlowLoopIterationSummary],
        runID: String
    ) async throws -> FlowArtifactBinding {
        try await persistJSON(
            iterations,
            id: "agent-loop-iterations",
            path: ".xcircuite/runs/\(runID)/loop/iterations.jsonl",
            runID: runID
        )
    }

    func persistAgentLoopSnapshot(
        _ snapshot: FlowAgentLoopSnapshot
    ) async throws -> FlowArtifactBinding {
        try await persistJSON(
            snapshot,
            id: "agent-loop-snapshot",
            path: ".xcircuite/runs/\(snapshot.runID)/loop/snapshot.json",
            runID: snapshot.runID
        )
    }

    private func persistJSON<Value: Encodable & Sendable>(
        _ value: Value,
        id: String,
        path: String,
        runID: String
    ) async throws -> FlowArtifactBinding {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try await persistArtifact(
            content: encoder.encode(value),
            logicalID: id,
            relativePath: try FlowArtifactPath.relative(normalizedRelativePath(path)),
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: .report,
                format: .json
            ),
            runID: runID,
            producer: nil,
            mode: .replaceable
        )
    }

    private func artifactURL(relativePath: ArtifactRelativePath) throws -> URL {
        projectRoot
            .appending(path: ".xcircuite", directoryHint: .isDirectory)
            .appending(path: relativePath.stringValue)
    }

    private func artifactRootID() throws -> ArtifactRootID {
        try ArtifactRootID(rawValue: "test-workspace")
    }

    private func normalizedRelativePath(_ path: String) -> String {
        path.hasPrefix(".xcircuite/")
            ? String(path.dropFirst(".xcircuite/".count))
            : path
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
                rootID: artifactRootID(),
                relativePath: relativePath
            ),
            producer: producer
        )
    }

    private func sameMaterializationPath(
        _ left: FlowArtifactBinding,
        _ right: FlowArtifactBinding
    ) -> Bool {
        switch (left.availability, right.availability) {
        case (.local(_, let leftRoot, let leftPath), .local(_, let rightRoot, let rightPath)):
            return leftRoot == rightRoot && leftPath == rightPath
        case (.service(_, let leftResource), .service(_, let rightResource)):
            return leftResource == rightResource
        default:
            return false
        }
    }

    private func persistProjections(for ledger: FlowRunLedger) throws {
        let runDirectory = projectRoot.appending(path: ".xcircuite/runs/\(ledger.runID)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        var generatedBindings: [FlowArtifactBinding] = []
        if let plan = ledger.plan {
            generatedBindings.append(try writeProjectionReference(
                plan,
                id: "run-plan",
                path: ".xcircuite/runs/\(ledger.runID)/plan.json",
                role: .input,
                to: runDirectory.appending(path: "plan.json"),
                runID: ledger.runID
            ))
        }
        if let toolchain = ledger.toolchain {
            generatedBindings.append(try writeProjectionReference(
                toolchain,
                id: "toolchain-manifest",
                path: ".xcircuite/runs/\(ledger.runID)/toolchain.json",
                role: .output,
                to: runDirectory.appending(path: "toolchain.json"),
                runID: ledger.runID
            ))
        }
        for stage in ledger.stages {
            do {
                try FlowIdentifierValidator().validate(stage.stageID, kind: .stageID)
            } catch {
                continue
            }
            let stageDirectory = runDirectory.appending(path: "stages/\(stage.stageID)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: stageDirectory, withIntermediateDirectories: true)
            generatedBindings.append(try writeProjectionReference(
                stage,
                id: "\(stage.stageID)-result",
                path: ".xcircuite/runs/\(ledger.runID)/stages/\(stage.stageID)/result.json",
                role: .output,
                to: stageDirectory.appending(path: "result.json"),
                runID: ledger.runID
            ))
        }
        for approval in ledger.approvals {
            generatedBindings.append(try writeProjectionReference(
                approval,
                id: "approval-\(approval.stageID)",
                path: ".xcircuite/runs/\(ledger.runID)/approvals/\(approval.stageID).json",
                role: .output,
                to: runDirectory.appending(path: "approvals/\(approval.stageID).json"),
                runID: ledger.runID
            ))
        }
        if !ledger.actions.isEmpty {
            generatedBindings.append(try writeJSONLinesReference(
                ledger.actions,
                id: "action-ledger",
                path: ".xcircuite/runs/\(ledger.runID)/actions.jsonl",
                to: runDirectory.appending(path: "actions.jsonl"),
                runID: ledger.runID
            ))
        }
        if let designDiff = ledger.designDiff {
            generatedBindings.append(try writeProjectionReference(
                designDiff,
                id: "design-diff",
                path: ".xcircuite/runs/\(ledger.runID)/design-diff.json",
                role: .output,
                to: runDirectory.appending(path: "design-diff.json"),
                runID: ledger.runID
            ))
        }

        var stored = ledger
        for binding in generatedBindings {
            stored.artifacts.removeAll { sameMaterializationPath($0, binding) }
            stored.artifacts.append(binding)
            bindingsByContentID[binding.reference.id] = binding
        }
        try persistManifestProjection(for: stored)
    }

    private func persistManifestProjection(for ledger: FlowRunLedger) throws {
        let runDirectory = projectRoot.appending(
            path: ".xcircuite/runs/\(ledger.runID)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        var stored = ledger
        stored.artifacts.sort { $0.availabilityDescription < $1.availabilityDescription }
        stored.runManifest.artifacts = stored.artifacts.filter {
            $0.logicalID != "run-manifest"
        }
        try writeProjection(
            stored.runManifest,
            to: runDirectory.appending(path: "manifest.json")
        )
        let manifestBinding = try fileReference(
            forProjectRelativePath: ".xcircuite/runs/\(stored.runID)/manifest.json",
            artifactID: "run-manifest",
            kind: .report,
            format: .json,
            inProjectAt: projectRoot,
            producerRunID: stored.runID
        )
        stored.artifacts.removeAll { sameMaterializationPath($0, manifestBinding) }
        stored.artifacts.append(manifestBinding)
        stored.artifacts.sort { $0.availabilityDescription < $1.availabilityDescription }
        if let evidence = stored.evidence {
            stored.evidence = try EvidenceManifest.contentAddressed(
                provenance: evidence.provenance,
                artifacts: stored.artifacts.map(\.reference),
                digester: SHA256ContentDigester()
            )
        }
        ledgers[runKey(runID: stored.runID, projectRoot: projectRoot)] = stored
    }

    private func writeProjection<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func writeProjectionReference<Value: Encodable>(
        _ value: Value,
        id: String,
        path: String,
        role: ArtifactRole,
        to url: URL,
        runID: String
    ) throws -> FlowArtifactBinding {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return try makeBinding(
            content: data,
            logicalID: id,
            relativePath: try FlowArtifactPath.relative(normalizedRelativePath(path)),
            descriptor: ArtifactDescriptor(
                role: role,
                kind: .other,
                format: .json
            ),
            producer: try ProducerIdentity(kind: .engine, identifier: runID, version: "1")
        )
    }

    private func writeJSONLinesReference<Value: Encodable>(
        _ values: [Value],
        id: String,
        path: String,
        to url: URL,
        runID: String
    ) throws -> FlowArtifactBinding {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for value in values {
            data.append(try encoder.encode(value))
            data.append(Data("\n".utf8))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return try makeBinding(
            content: data,
            logicalID: id,
            relativePath: try FlowArtifactPath.relative(normalizedRelativePath(path)),
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: .other,
                format: .text
            ),
            producer: try ProducerIdentity(kind: .engine, identifier: runID, version: "1")
        )
    }

    private func runKey(runID: String, projectRoot: URL) -> String {
        "\(Self.canonicalRoot(projectRoot).path(percentEncoded: false))\u{001F}\(runID)"
    }

    private func approvalKey(runID: String, stageID: String, projectRoot: URL) -> String {
        "\(runKey(runID: runID, projectRoot: projectRoot))\u{001F}\(stageID)"
    }

    private static func canonicalRoot(_ root: URL) -> URL {
        root.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func isContained(_ candidate: URL, by root: URL) -> Bool {
        canonicalPath(candidate).hasPrefix(canonicalPath(root) + "/")
    }

    private static func canonicalPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath()
            .path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/var" || path.hasPrefix("/var/") || path == "/tmp" || path.hasPrefix("/tmp/") {
            return "/private\(path)"
        }
        return path
    }
}

private actor TestFlowInfrastructureRegistry {
    private var infrastructures: [String: TestFlowInfrastructure] = [:]

    func infrastructure(for projectRoot: URL) -> TestFlowInfrastructure {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let key = root.path(percentEncoded: false)
        if let existing = infrastructures[key] {
            return existing
        }
        let infrastructure = TestFlowInfrastructure(projectRoot: root)
        infrastructures[key] = infrastructure
        return infrastructure
    }
}

func makeTestOrchestrator(projectRoot: URL) async throws -> DefaultFlowOrchestrator {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowOrchestrator(
        infrastructure: infrastructure,
        ledgerPersistence: infrastructure,
        producer: try ProducerIdentity(
            kind: .library,
            identifier: "design-flow-kernel-tests",
            version: "1"
        ),
        progressStore: FlowRunProgressStore(persistence: infrastructure)
    )
}

func makeTestDecisionPacketBuilder(projectRoot: URL) async -> DefaultFlowRunDecisionPacketBuilder {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunDecisionPacketBuilder(
        reviewBundler: DefaultFlowRunReviewBundler(
            loader: infrastructure,
            persistence: infrastructure
        ),
        persistence: infrastructure
    )
}

func makeTestLedgerInspector(projectRoot: URL) async -> DefaultFlowRunLedgerInspector {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunLedgerInspector(
        reviewBundler: DefaultFlowRunReviewBundler(
            loader: infrastructure,
            persistence: infrastructure
        )
    )
}

func makeTestApprovalRecorder(projectRoot: URL) async -> DefaultFlowGateApprovalRecorder {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowGateApprovalRecorder(
        loader: infrastructure,
        inspector: DefaultFlowRunLedgerInspector(
            reviewBundler: DefaultFlowRunReviewBundler(
                loader: infrastructure,
                persistence: infrastructure
            )
        ),
        approvalPersistence: infrastructure,
        artifactLocationValidator: DefaultFlowRunArtifactLocationValidator()
    )
}

func makeTestReviewBundler(projectRoot: URL) async -> DefaultFlowRunReviewBundler {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunReviewBundler(
        loader: infrastructure,
        persistence: infrastructure
    )
}

func makeTestDecisionPacketValidator(projectRoot: URL) async -> DefaultFlowRunDecisionPacketValidator {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunDecisionPacketValidator(
        loader: infrastructure,
        persistence: infrastructure,
        reviewBundler: DefaultFlowRunReviewBundler(
            loader: infrastructure,
            persistence: infrastructure
        ),
        artifactLocationValidator: DefaultFlowRunArtifactLocationValidator()
    )
}

func makeTestReleaseEnvelopeBuilder(
    projectRoot: URL,
    currentDate: Date = Date()
) async -> DefaultFlowRunReleaseEnvelopeBuilder {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunReleaseEnvelopeBuilder(
        decisionPacketValidator: await makeTestDecisionPacketValidator(projectRoot: projectRoot),
        loader: infrastructure,
        persistence: infrastructure,
        currentDate: currentDate
    )
}

func makeTestStageArtifactLadderBuilder(projectRoot: URL) async -> DefaultFlowRunStageArtifactLadderBuilder {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunStageArtifactLadderBuilder(
        loader: infrastructure,
        reviewBundler: DefaultFlowRunReviewBundler(
            loader: infrastructure,
            persistence: infrastructure
        ),
        persistence: infrastructure
    )
}

func makeTestRunResumer(projectRoot: URL) async throws -> DefaultFlowRunResumer {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunResumer(
        loader: infrastructure,
        orchestrator: try await makeTestOrchestrator(projectRoot: projectRoot),
        inspector: DefaultFlowRunLedgerInspector(
            reviewBundler: DefaultFlowRunReviewBundler(
                loader: infrastructure,
                persistence: infrastructure
            )
        ),
        artifactPersistence: infrastructure,
        artifactLocationValidator: DefaultFlowRunArtifactLocationValidator()
    )
}

func makeTestProgressSubscriber(projectRoot: URL) async -> DefaultFlowRunProgressSubscriber {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunProgressSubscriber(
        progressStore: FlowRunProgressStore(persistence: infrastructure)
    )
}

func makeTestCancellationRecorder(projectRoot: URL) async -> DefaultFlowRunCancellationRecorder {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunCancellationRecorder(
        progressStore: FlowRunProgressStore(persistence: infrastructure)
    )
}

func makeTestReleaseEvidenceCollector(
    projectRoot: URL,
    currentDate: Date = Date()
) async throws -> DefaultFlowRunReleaseEvidenceCollector {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunReleaseEvidenceCollector(
        persistence: infrastructure,
        producer: try ProducerIdentity(
            kind: .engine,
            identifier: "design-flow-kernel.release-evidence-collector",
            version: "1.0.0"
        ),
        currentDate: currentDate
    )
}

func makeTestInputArtifactReference(
    at url: URL,
    artifactID: String,
    projectRoot: URL
) async throws -> FlowArtifactBinding {
    func canonicalPath(_ candidate: URL) -> String {
        var path = candidate.standardizedFileURL.resolvingSymlinksInPath()
            .path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/var" || path.hasPrefix("/var/") || path == "/tmp" || path.hasPrefix("/tmp/") {
            return "/private\(path)"
        }
        return path
    }
    let rootPath = canonicalPath(projectRoot)
    let filePath = canonicalPath(url)
    guard filePath.hasPrefix(rootPath + "/") else {
        throw FlowRunLedgerPersistenceError.storageFailed(
            "test input lies outside project root: candidate=\(filePath) root=\(rootPath)"
        )
    }
    let relativePath = String(filePath.dropFirst(rootPath.count + 1))
    return try await TestFlowInfrastructure.bound(to: projectRoot).fileReference(
        forProjectRelativePath: relativePath,
        artifactID: artifactID,
        role: .input,
        kind: .report,
        format: .json,
        inProjectAt: projectRoot
    )
}

func collectTestReleaseEvidence(
    runID: String,
    projectRoot: URL,
    signoffDashboardURL: URL,
    contractReportURL: URL,
    currentDate: Date = Date()
) async throws -> FlowRunReleaseEvidenceCollectionResult {
    let dashboard = try await makeTestInputArtifactReference(
        at: signoffDashboardURL,
        artifactID: "source-signoff-dashboard",
        projectRoot: projectRoot
    )
    let contract = try await makeTestInputArtifactReference(
        at: contractReportURL,
        artifactID: "source-contract-report",
        projectRoot: projectRoot
    )
    return try await makeTestReleaseEvidenceCollector(
        projectRoot: projectRoot,
        currentDate: currentDate
    ).collectReleaseEvidence(
        runID: runID,
        workspaceID: try testWorkspaceID(for: projectRoot),
        signoffDashboard: dashboard,
        contractReport: contract
    )
}

func makeTestRetentionIndexBuilder(projectRoot: URL) async -> DefaultFlowRunReleaseRetentionIndexBuilder {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunReleaseRetentionIndexBuilder(
        persistence: infrastructure,
        validator: DefaultFlowRunReleaseRetentionIndexValidator(persistence: infrastructure)
    )
}

struct TestArtifactReference: Sendable, Hashable {
    var artifactID: String?
    var path: String
    var role: ArtifactRole
    var kind: ArtifactKind
    var format: ArtifactFormat
    var sha256: String?
    var byteCount: Int64?
    var producerRunID: String?

    init(
        artifactID: String? = nil,
        path: String,
        role: ArtifactRole = .output,
        kind: ArtifactKind,
        format: ArtifactFormat,
        sha256: String? = nil,
        byteCount: Int64? = nil,
        producerRunID: String? = nil
    ) {
        self.artifactID = artifactID
        self.path = path
        self.role = role
        self.kind = kind
        self.format = format
        self.sha256 = sha256
        self.byteCount = byteCount
        self.producerRunID = producerRunID
    }
}

func makeTestReviewArtifact(
    purpose: FlowRunReviewArtifactPurpose,
    artifactID: String,
    stageID: String? = nil,
    path: String,
    kind: ArtifactKind,
    format: ArtifactFormat,
    sha256: String = String(repeating: "0", count: 64),
    byteCount: UInt64 = 0,
    integrity: FlowRunReviewArtifactIntegrity? = nil
) throws -> FlowRunReviewArtifact {
    let reference = try ArtifactReference(
        digest: ContentDigest(algorithm: .sha256, hexadecimalValue: sha256),
        byteCount: byteCount,
        descriptor: ArtifactDescriptor(
            role: .output,
            kind: kind,
            format: format
        )
    )
    let normalizedPath = path.hasPrefix(".xcircuite/")
        ? String(path.dropFirst(".xcircuite/".count))
        : path
    return FlowRunReviewArtifact(
        binding: try FlowArtifactBinding(
            logicalID: artifactID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(rawValue: "test-workspace"),
                relativePath: FlowArtifactPath.relative(normalizedPath)
            )
        ),
        purpose: purpose,
        stageID: stageID,
        integrity: integrity
    )
}

struct TestContentDigester {
    func sha256(data: Data) throws -> String {
        try SHA256ContentDigester().digest(data: data).hexadecimalValue
    }

    func sha256(fileAt url: URL) throws -> String {
        try SHA256ContentDigester().digest(fileAt: url).hexadecimalValue
    }

    func byteCount(fileAt url: URL) throws -> Int64 {
        Int64(try Data(contentsOf: url).count)
    }
}

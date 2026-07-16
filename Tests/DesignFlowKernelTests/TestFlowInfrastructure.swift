import CircuiteFoundation
import Foundation
@testable import DesignFlowKernel

func testWorkspaceID(for root: URL) throws -> FlowWorkspaceID {
    try FlowWorkspaceID(
        rawValue: ArtifactID(stableKey: root.standardizedFileURL.path(percentEncoded: false)).rawValue
    )
}

actor TestFlowInfrastructure: FlowRunInfrastructure, FlowRunLedgerPersisting {
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

    init(projectRoot: URL) {
        self.projectRoot = Self.canonicalRoot(projectRoot)
    }

    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        try await loadArtifactContent(for: reference)
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
        let persistedStageIDs = ledger.plan.map {
            Array($0.stages.prefix(ledger.stages.count)).map(\.stageID)
        } ?? ledger.stages.map(\.stageID)
        for stageID in persistedStageIDs {
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
        if let plan = ledger.plan {
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

    func saveRunLedger(_ proposed: FlowRunLedger) async throws {
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
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference {
        let persistedLocator = try projectRelativeLocator(from: locator)
        let url = try artifactURL(locator: persistedLocator, projectRoot: projectRoot)
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
                "artifact already exists: \(locator.location.value)"
            )
        case .immutable where destinationExists:
            let existing = try Data(contentsOf: url)
            guard existing == content else {
                throw FlowRunLedgerPersistenceError.storageFailed(
                    "immutable artifact conflict: \(locator.location.value)"
                )
            }
        case .createOnly, .immutable, .replaceable:
            try content.write(to: url, options: .atomic)
        }
        let reference = ArtifactReference(
            id: id,
            locator: persistedLocator,
            digest: try SHA256ContentDigester().digest(data: content),
            byteCount: UInt64(content.count),
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: runID,
                version: "1"
            )
        )
        let key = runKey(runID: runID, projectRoot: projectRoot)
        if var ledger = ledgers[key] {
            ledger.artifacts.removeAll {
                $0.id == reference.id || $0.locator.location == reference.locator.location
            }
            ledger.artifacts.append(reference)
            ledger.artifacts.sort { $0.path < $1.path }
            ledger.runManifest.artifacts = ledger.artifacts
            ledger.runManifest.revision += 1
            ledger.runManifest.updatedAt = Date()
            ledgers[key] = ledger
            try persistProjections(for: ledger)
        }
        return reference
    }

    func loadArtifactContent(
        for reference: ArtifactReference
    ) async throws -> Data {
        let url = try artifactURL(locator: reference.locator, projectRoot: projectRoot)
        let data = try Data(contentsOf: url)
        let digest = try SHA256ContentDigester().digest(data: data)
        guard digest == reference.digest, UInt64(data.count) == reference.byteCount else {
            throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                path: reference.locator.location.value,
                reason: "digest or byte count mismatch"
            )
        }
        return data
    }

    func loadArtifactContent(
        at locator: ArtifactLocator
    ) async throws -> Data? {
        let directURL = try artifactURL(locator: locator, projectRoot: projectRoot)
        if FileManager.default.fileExists(atPath: directURL.path(percentEncoded: false)) {
            return try Data(contentsOf: directURL)
        }
        let persistedURL = try artifactURL(
            locator: projectRelativeLocator(from: locator),
            projectRoot: projectRoot
        )
        guard FileManager.default.fileExists(atPath: persistedURL.path(percentEncoded: false)) else {
            return nil
        }
        return try Data(contentsOf: persistedURL)
    }

    func artifactExists(at locator: ArtifactLocator) async throws -> Bool {
        let directURL = try artifactURL(locator: locator, projectRoot: projectRoot)
        if FileManager.default.fileExists(atPath: directURL.path(percentEncoded: false)) {
            return true
        }
        return FileManager.default.fileExists(
            atPath: try artifactURL(
                locator: projectRelativeLocator(from: locator),
                projectRoot: projectRoot
            ).path(percentEncoded: false)
        )
    }

    func verifyArtifact(_ reference: ArtifactReference) async -> ArtifactIntegrity {
        LocalArtifactVerifier().verify(reference, relativeTo: projectRoot)
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
        _ references: [ArtifactReference],
        runID: String,
        inProjectAt projectRoot: URL
    ) throws {
        for reference in references {
            try upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
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
        if let selection = try FlowSuggestedCommandSelection(record: action) {
            ledger.suggestedCommandSelections.append(selection)
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
        kind: ArtifactKind,
        format: ArtifactFormat,
        inProjectAt projectRoot: URL,
        producerRunID: String? = nil
    ) throws -> ArtifactReference {
        let data = try Data(contentsOf: projectRoot.appending(path: path))
        return ArtifactReference(
            id: try artifactID.map(ArtifactID.init(rawValue:)),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: kind,
                format: format
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
            producer: try producerRunID.map {
                try ProducerIdentity(kind: .engine, identifier: $0, version: "1")
            }
        )
    }

    func upsertRunArtifact(
        _ reference: ArtifactReference,
        runID: String,
        inProjectAt projectRoot: URL
    ) throws {
        let key = runKey(runID: runID, projectRoot: projectRoot)
        guard var ledger = ledgers[key] else {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        }
        ledger.artifacts.removeAll { $0.id == reference.id || $0.locator.location == reference.locator.location }
        ledger.artifacts.append(reference)
        ledger.runManifest.artifacts = ledger.artifacts
        ledger.runManifest.revision += 1
        ledger.runManifest.updatedAt = Date()
        ledgers[key] = ledger
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
            id: ArtifactID(rawValue: "run-progress"),
            locator: ArtifactLocator(
                location: ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/runs/\(event.runID)/progress.jsonl"
                ),
                role: .output,
                kind: .report,
                format: .text
            ),
            runID: event.runID,
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
    ) async throws -> ArtifactReference {
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

    func runControlArtifacts(runID: String) async throws -> [ArtifactReference] {
        let ledger: FlowRunLedger
        do {
            ledger = try await loadRunLedger(runID: runID)
        } catch FlowRunLedgerPersistenceError.resumeTargetNotFound {
            return []
        }
        return ledger.artifacts.filter {
            $0.id.rawValue == "run-progress" || $0.id.rawValue == "run-cancellation-request"
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
        let reference = try await persistJSON(
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
        ledger.artifacts.removeAll { $0.id == reference.id || $0.locator.location == reference.locator.location }
        ledger.artifacts.append(reference)
        ledger.runManifest.artifacts = ledger.artifacts
        ledger.runManifest.revision += 1
        ledger.runManifest.updatedAt = Date()
        ledgers[key] = ledger
    }

    func persistCrossArtifactEvaluation(
        _ evaluation: FlowCrossArtifactEvaluation
    ) async throws -> ArtifactReference {
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
    ) async throws -> ArtifactReference {
        try await persistJSON(
            iterations,
            id: "agent-loop-iterations",
            path: ".xcircuite/runs/\(runID)/loop/iterations.jsonl",
            runID: runID
        )
    }

    func persistAgentLoopSnapshot(
        _ snapshot: FlowAgentLoopSnapshot
    ) async throws -> ArtifactReference {
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
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try await persistArtifact(
            content: encoder.encode(value),
            id: try ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .report,
                format: .json
            ),
            runID: runID,
            mode: .replaceable
        )
    }

    private func artifactURL(locator: ArtifactLocator, projectRoot: URL) throws -> URL {
        guard locator.location.storage == .workspaceRelative else {
            throw FlowRunLedgerPersistenceError.storageFailed("absolute test artifact location")
        }
        let path = locator.location.value
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            throw FlowRunLedgerPersistenceError.storageFailed("unsafe test artifact path: \(path)")
        }
        return projectRoot.appending(path: path)
    }

    private func projectRelativeLocator(from locator: ArtifactLocator) throws -> ArtifactLocator {
        guard locator.location.storage == .workspaceRelative else {
            return locator
        }
        let value = locator.location.value
        guard !value.hasPrefix(".xcircuite/") else {
            return locator
        }
        return ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: ".xcircuite/\(value)"),
            role: locator.role,
            kind: locator.kind,
            format: locator.format
        )
    }

    private func persistProjections(for ledger: FlowRunLedger) throws {
        let runDirectory = projectRoot.appending(path: ".xcircuite/runs/\(ledger.runID)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        var generatedReferences: [ArtifactReference] = []
        if let plan = ledger.plan {
            generatedReferences.append(try writeProjectionReference(
                plan,
                id: "run-plan",
                path: ".xcircuite/runs/\(ledger.runID)/plan.json",
                role: .input,
                to: runDirectory.appending(path: "plan.json"),
                runID: ledger.runID
            ))
        }
        if let toolchain = ledger.toolchain {
            generatedReferences.append(try writeProjectionReference(
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
            generatedReferences.append(try writeProjectionReference(
                stage,
                id: "\(stage.stageID)-result",
                path: ".xcircuite/runs/\(ledger.runID)/stages/\(stage.stageID)/result.json",
                role: .output,
                to: stageDirectory.appending(path: "result.json"),
                runID: ledger.runID
            ))
        }
        for approval in ledger.approvals {
            generatedReferences.append(try writeProjectionReference(
                approval,
                id: "approval-\(approval.stageID)",
                path: ".xcircuite/runs/\(ledger.runID)/approvals/\(approval.stageID).json",
                role: .output,
                to: runDirectory.appending(path: "approvals/\(approval.stageID).json"),
                runID: ledger.runID
            ))
        }
        if !ledger.actions.isEmpty {
            generatedReferences.append(try writeJSONLinesReference(
                ledger.actions,
                id: "action-ledger",
                path: ".xcircuite/runs/\(ledger.runID)/actions.jsonl",
                to: runDirectory.appending(path: "actions.jsonl"),
                runID: ledger.runID
            ))
        }
        if let designDiff = ledger.designDiff {
            generatedReferences.append(try writeProjectionReference(
                designDiff,
                id: "design-diff",
                path: ".xcircuite/runs/\(ledger.runID)/design-diff.json",
                role: .output,
                to: runDirectory.appending(path: "design-diff.json"),
                runID: ledger.runID
            ))
        }

        var stored = ledger
        for reference in generatedReferences {
            stored.artifacts.removeAll { $0.id == reference.id || $0.path == reference.path }
            stored.artifacts.append(reference)
        }
        stored.artifacts.sort { $0.path < $1.path }
        stored.runManifest.artifacts = stored.artifacts.filter {
            $0.id.rawValue != "run-manifest"
        }
        try writeProjection(stored.runManifest, to: runDirectory.appending(path: "manifest.json"))
        let manifestReference = try fileReference(
            forProjectRelativePath: ".xcircuite/runs/\(ledger.runID)/manifest.json",
            artifactID: "run-manifest",
            kind: .report,
            format: .json,
            inProjectAt: projectRoot,
            producerRunID: ledger.runID
        )
        stored.artifacts.removeAll { $0.id == manifestReference.id || $0.path == manifestReference.path }
        stored.artifacts.append(manifestReference)
        stored.artifacts.sort { $0.path < $1.path }
        ledgers[runKey(runID: ledger.runID, projectRoot: projectRoot)] = stored
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
    ) throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: role,
                kind: .other,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
            producer: try ProducerIdentity(kind: .engine, identifier: runID, version: "1")
        )
    }

    private func writeJSONLinesReference<Value: Encodable>(
        _ values: [Value],
        id: String,
        path: String,
        to url: URL,
        runID: String
    ) throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for value in values {
            data.append(try encoder.encode(value))
            data.append(Data("\n".utf8))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .other,
                format: .text
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
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
        ledgerPersistence: infrastructure
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
        )
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
        artifactPersistence: infrastructure
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
) async -> DefaultFlowRunReleaseEvidenceCollector {
    let infrastructure = await TestFlowInfrastructure.bound(to: projectRoot)
    return DefaultFlowRunReleaseEvidenceCollector(
        persistence: infrastructure,
        currentDate: currentDate
    )
}

func makeTestInputArtifactReference(
    at url: URL,
    artifactID: String,
    projectRoot: URL
) async throws -> ArtifactReference {
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
    var kind: ArtifactKind
    var format: ArtifactFormat
    var sha256: String?
    var byteCount: Int64?
    var producerRunID: String?

    init(
        artifactID: String? = nil,
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        sha256: String? = nil,
        byteCount: Int64? = nil,
        producerRunID: String? = nil
    ) {
        self.artifactID = artifactID
        self.path = path
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
    FlowRunReviewArtifact(
        reference: ArtifactReference(
            id: try ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: kind,
                format: format
            ),
            digest: try ContentDigest(algorithm: .sha256, hexadecimalValue: sha256),
            byteCount: byteCount
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

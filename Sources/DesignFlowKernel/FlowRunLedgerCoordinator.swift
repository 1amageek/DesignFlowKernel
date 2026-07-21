import CircuiteFoundation
import Foundation

/// Serializes typed run-ledger updates behind the kernel persistence protocol.
///
/// The coordinator owns lifecycle ordering only. Storage format, filesystem
/// boundaries, and recovery details remain in the injected implementation.
public actor FlowRunLedgerCoordinator {
    private let persistence: any FlowRunLedgerPersisting

    public init(persistence: any FlowRunLedgerPersisting) {
        self.persistence = persistence
    }

    public func load(
        runID: String
    ) async throws -> FlowRunLedger {
        try await persistence.loadRunLedger(runID: runID)
    }

    @discardableResult
    public func create(
        _ ledger: FlowRunLedger
    ) async throws -> FlowRunLedger {
        guard ledger.runManifest.status == .created,
              ledger.runManifest.revision == 0,
              ledger.runManifest.startedAt == nil,
              ledger.runManifest.finishedAt == nil,
              ledger.runManifest.artifacts.isEmpty,
              ledger.stages.isEmpty,
              ledger.toolchain == nil,
              ledger.designDiff == nil,
              ledger.progressEvents.isEmpty,
              ledger.cancellationRequest == nil,
              ledger.evidence == nil,
              ledger.artifacts.isEmpty,
              ledger.actions.isEmpty,
              ledger.suggestedActionSelections.isEmpty,
              ledger.approvals.isEmpty else {
            throw FlowRunLedgerPersistenceError.invalidInitialProjection(
                runID: ledger.runID,
                issue: .containsLifecycleProjection
            )
        }
        return try await persistence.createRunLedger(ledger)
    }

    private func persist(_ ledger: FlowRunLedger) async throws -> FlowRunLedger {
        try await persistence.saveRunLedger(ledger)
    }

    @discardableResult
    public func update(
        runID: String,
        _ mutation: @Sendable (inout FlowRunLedger) throws -> Void
    ) async throws -> FlowRunLedger {
        try await update(
            runID: runID,
            allowsProtectedProjectionMutation: false,
            mutation
        )
    }

    private func update(
        runID: String,
        allowsProtectedProjectionMutation: Bool,
        _ mutation: @Sendable (inout FlowRunLedger) throws -> Void
    ) async throws -> FlowRunLedger {
        var ledger = try await load(runID: runID)
        guard ledger.runID == runID else {
            throw FlowRunLedgerPersistenceError.runIdentifierMismatch(
                requested: runID,
                stored: ledger.runID
            )
        }
        let originalLedger = ledger
        let originalRunID = ledger.runID
        let originalManifest = ledger.runManifest
        let originalStages = ledger.stages
        let originalToolchain = ledger.toolchain
        let originalEvidence = ledger.evidence
        let originalArtifacts = ledger.artifacts
        let originalPlan = ledger.plan
        let originalDesignDiff = ledger.designDiff
        let originalProgressEvents = ledger.progressEvents
        let originalCancellationRequest = ledger.cancellationRequest
        let originalActions = ledger.actions
        let originalSuggestedActionSelections = ledger.suggestedActionSelections
        let originalRevision = ledger.runManifest.revision
        let originalUpdatedAt = ledger.runManifest.updatedAt
        try mutation(&ledger)
        if ledger == originalLedger {
            return originalLedger
        }
        if originalManifest.status.isTerminal {
            let actionsAreAppendOnly = ledger.actions.starts(with: originalActions)
            let selectionsAreAppendOnly = ledger.suggestedActionSelections.starts(
                with: originalSuggestedActionSelections
            )
            let appendedActions = ledger.actions.dropFirst(originalActions.count)
            let appendedSelections = ledger.suggestedActionSelections.dropFirst(
                originalSuggestedActionSelections.count
            )
            let projectedSelections = try appendedActions.compactMap {
                try FlowRunSuggestedActionSelection(record: $0)
            }
            let immutableTerminalFields: [(String, Bool)] = [
                ("plan", ledger.plan == originalPlan),
                ("designDiff", ledger.designDiff == originalDesignDiff),
                ("progressEvents", ledger.progressEvents == originalProgressEvents),
                ("cancellationRequest", ledger.cancellationRequest == originalCancellationRequest),
                ("actions", actionsAreAppendOnly),
                (
                    "suggestedActionSelections",
                    selectionsAreAppendOnly && Array(appendedSelections) == projectedSelections
                ),
            ]
            if let changed = immutableTerminalFields.first(where: { !$0.1 }) {
                throw FlowRunLedgerPersistenceError.protectedProjectionMutation(
                    runID: runID,
                    field: changed.0
                )
            }
        }
        guard ledger.runManifest.revision == originalRevision else {
            throw FlowRunLedgerPersistenceError.storageFailed(
                "Ledger mutations must not modify revision directly."
            )
        }
        guard ledger.runID == originalRunID else {
            throw FlowRunLedgerPersistenceError.protectedProjectionMutation(
                runID: runID,
                field: "runID"
            )
        }
        if !allowsProtectedProjectionMutation {
            let protectedFields: [(String, Bool)] = [
                ("runManifest", ledger.runManifest == originalManifest),
                ("stages", ledger.stages == originalStages),
                ("toolchain", ledger.toolchain == originalToolchain),
                ("evidence", ledger.evidence == originalEvidence),
                ("artifacts", ledger.artifacts == originalArtifacts),
            ]
            if let changed = protectedFields.first(where: { !$0.1 }) {
                throw FlowRunLedgerPersistenceError.protectedProjectionMutation(
                    runID: runID,
                    field: changed.0
                )
            }
        }
        ledger.runManifest.revision = originalRevision + 1
        ledger.runManifest.updatedAt = max(Date(), originalUpdatedAt)
        return try await persist(ledger)
    }

    @discardableResult
    public func transition(
        runID: String,
        to status: FlowRunStatus,
        registering artifacts: [ArtifactReference] = [],
        at timestamp: Date = Date()
    ) async throws -> FlowRunLedger {
        guard !status.isTerminal else {
            throw FlowRunLedgerPersistenceError.invalidTransition(
                runID: runID,
                from: "nonterminal-transition-api",
                to: status.rawValue
            )
        }
        return try await update(
            runID: runID,
            allowsProtectedProjectionMutation: true
        ) { ledger in
            let next = try Self.validateTransition(
                runID: runID,
                current: ledger.runManifest.status,
                requested: status
            )
            Self.applyTransition(next, to: &ledger.runManifest, at: timestamp)
            ledger.artifacts = try mergedArtifactReferences(ledger.artifacts + artifacts)
        }
    }

    /// Commits the terminal run projection with its evidence in one ledger save.
    ///
    /// All referenced artifacts must already be durably persisted and verified
    /// before this method is called. The single mutation prevents a terminal
    /// manifest from becoming visible without its stages, toolchain, evidence,
    /// and artifact inventory.
    @discardableResult
    public func finalize(
        runID: String,
        status: FlowRunStatus,
        stages: [FlowStageResult],
        toolchain: FlowToolchainManifest,
        evidence: EvidenceManifest,
        artifacts: [ArtifactReference],
        at timestamp: Date = Date()
    ) async throws -> FlowRunLedger {
        try Self.validateTerminalProjection(
            runID: runID,
            status: status,
            stages: stages,
            toolchain: toolchain,
            evidence: evidence,
            artifacts: artifacts
        )
        return try await update(
            runID: runID,
            allowsProtectedProjectionMutation: true
        ) { ledger in
            let next = try Self.validateTransition(
                runID: runID,
                current: ledger.runManifest.status,
                requested: status
            )
            guard next != .created, next != .running else {
                throw FlowRunLedgerPersistenceError.invalidTransition(
                    runID: runID,
                    from: ledger.runManifest.status.rawValue,
                    to: next.rawValue
                )
            }
            ledger.stages = stages
            ledger.toolchain = toolchain
            ledger.evidence = evidence
            ledger.artifacts = artifacts
            ledger.runManifest.artifacts = artifacts
            Self.applyTransition(next, to: &ledger.runManifest, at: timestamp)
        }
    }

    /// Finalizes a created or running run when execution cannot continue.
    ///
    /// This is the only lifecycle operation that permits a direct
    /// `created -> failed` transition. It prevents a failed artifact or
    /// progress setup from leaving a resumable-looking orphan run.
    @discardableResult
    public func finalizeFailure(
        runID: String,
        stages: [FlowStageResult],
        toolchain: FlowToolchainManifest,
        provenance: ExecutionProvenance,
        at timestamp: Date = Date()
    ) async throws -> FlowRunLedger {
        return try await update(
            runID: runID,
            allowsProtectedProjectionMutation: true
        ) { ledger in
            guard ledger.runManifest.status == .created
                    || ledger.runManifest.status == .running else {
                throw FlowRunLedgerPersistenceError.invalidTransition(
                    runID: runID,
                    from: ledger.runManifest.status.rawValue,
                    to: FlowRunStatus.failed.rawValue
                )
            }
            let artifacts = ledger.artifacts
            let evidence = EvidenceManifest(
                provenance: provenance,
                artifacts: artifacts
            )
            try Self.validateTerminalProjection(
                runID: runID,
                status: .failed,
                stages: stages,
                toolchain: toolchain,
                evidence: evidence,
                artifacts: artifacts
            )
            ledger.stages = stages
            ledger.toolchain = toolchain
            ledger.evidence = evidence
            ledger.artifacts = artifacts
            ledger.runManifest.artifacts = artifacts
            Self.applyTransition(.failed, to: &ledger.runManifest, at: timestamp)
        }
    }

    /// Registers canonical artifacts without changing the run lifecycle state.
    ///
    /// Ledger and manifest projections are updated atomically so persistence
    /// implementations never need access to kernel-owned manifest setters.
    @discardableResult
    public func register(
        runID: String,
        artifacts: [ArtifactReference]
    ) async throws -> FlowRunLedger {
        try await update(
            runID: runID,
            allowsProtectedProjectionMutation: true
        ) { ledger in
            ledger.artifacts = try mergedArtifactReferences(ledger.artifacts + artifacts)
            ledger.runManifest.artifacts = ledger.artifacts
        }
    }

    /// Appends a typed action and its derived suggested-action selection.
    ///
    /// Terminal analysis evidence remains immutable. Human or agent review
    /// decisions may be appended after terminalization without granting the
    /// caller generic artifact or lifecycle projection mutation privileges.
    @discardableResult
    public func appendAction(
        _ action: FlowRunActionRecord
    ) async throws -> FlowRunLedger {
        try await update(runID: action.runID) { ledger in
            ledger = try FlowRunActionReducer().appending(action, to: ledger)
        }
    }

    private static func manifestStatus(_ status: FlowRunStatus) -> FlowRunStatus {
        switch status {
        case .created: .created
        case .running: .running
        case .succeeded: .succeeded
        case .failed: .failed
        case .blocked: .blocked
        case .cancelled: .cancelled
        case .partial: .partial
        }
    }

    private static func validateTransition(
        runID: String,
        current: FlowRunStatus,
        requested: FlowRunStatus
    ) throws -> FlowRunStatus {
        let next = manifestStatus(requested)
        guard current.canTransition(to: next) else {
            throw FlowRunLedgerPersistenceError.invalidTransition(
                runID: runID,
                from: current.rawValue,
                to: next.rawValue
            )
        }
        return next
    }

    private static func applyTransition(
        _ status: FlowRunStatus,
        to manifest: inout FlowRunManifest,
        at timestamp: Date
    ) {
        manifest.status = status
        switch status {
        case .created:
            break
        case .running:
            manifest.startedAt = manifest.startedAt ?? timestamp
            manifest.finishedAt = nil
        case .succeeded, .failed, .cancelled, .blocked, .partial:
            manifest.startedAt = manifest.startedAt ?? timestamp
            manifest.finishedAt = timestamp
        }
    }

    private static func validateTerminalProjection(
        runID: String,
        status: FlowRunStatus,
        stages: [FlowStageResult],
        toolchain: FlowToolchainManifest,
        evidence: EvidenceManifest,
        artifacts: [ArtifactReference]
    ) throws {
        func reject(_ issue: FlowTerminalProjectionIssue) throws -> Never {
            throw FlowRunLedgerPersistenceError.invalidTerminalProjection(
                runID: runID,
                issue: issue
            )
        }

        guard status.isTerminal else {
            try reject(.nonterminalStatus(status))
        }
        guard toolchain.runID == runID else {
            try reject(.toolchainRunIdentifierMismatch(
                expected: runID,
                actual: toolchain.runID
            ))
        }
        let stageIDs = stages.map(\.stageID)
        guard !stageIDs.isEmpty, Set(stageIDs).count == stageIDs.count else {
            try reject(.duplicateOrMissingStageIdentifiers)
        }
        if let stage = stages.first(where: { $0.status == .pending || $0.status == .running }) {
            try reject(.nonterminalStage(stageID: stage.stageID, status: stage.status))
        }
        for stage in stages {
            do {
                try DefaultFlowStageResultValidator().validate(
                    stage,
                    expectedStageID: stage.stageID
                )
            } catch FlowExecutionError.invalidStageResult(_, let issue) {
                try reject(.invalidStageResult(stageID: stage.stageID, issue: issue))
            } catch {
                throw error
            }
        }
        switch status {
        case .succeeded:
            guard stages.allSatisfy({ $0.status == .succeeded || $0.status == .skipped }) else {
                try reject(.succeededRunContainsUnsuccessfulStage)
            }
        case .failed:
            guard stages.contains(where: { $0.status == .failed }) else {
                try reject(.failedRunMissingFailedStage)
            }
        case .blocked, .cancelled:
            guard stages.contains(where: { $0.status == .blocked }) else {
                try reject(.blockedOrCancelledRunMissingBlockedStage)
            }
        case .partial:
            guard !stages.contains(where: { $0.status == .failed || $0.status == .blocked }),
                  stages.contains(where: { $0.status == .skipped }) else {
                try reject(.invalidPartialRunStages)
            }
        case .created, .running:
            try reject(.nonterminalStatus(status))
        }

        let artifactLocators = artifacts.map(\.locator)
        guard Set(artifactLocators).count == artifactLocators.count else {
            try reject(.duplicateArtifactLocator)
        }
        guard Set(evidence.artifacts) == Set(artifacts),
              evidence.artifacts.count == artifacts.count else {
            try reject(.evidenceArtifactInventoryMismatch)
        }
        guard Set(evidence.provenance.inputs).isSubset(of: Set(artifacts)) else {
            try reject(.provenanceInputNotRetained)
        }
        let artifactInventory = Set(artifacts)
        if let stage = stages.first(where: {
            !Set($0.artifacts).isSubset(of: artifactInventory)
        }) {
            try reject(.stageArtifactNotRetained(stageID: stage.stageID))
        }
        let toolchainStageIDs = toolchain.stages.map(\.stageID)
        guard Set(toolchainStageIDs).count == toolchainStageIDs.count,
              Set(toolchainStageIDs) == Set(stageIDs) else {
            try reject(.toolchainStageInventoryMismatch)
        }
    }
}

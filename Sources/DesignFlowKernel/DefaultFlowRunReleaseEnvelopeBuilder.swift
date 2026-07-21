import CircuiteFoundation
import Foundation

public struct DefaultFlowRunReleaseEnvelopeBuilder: FlowRunReleaseEnvelopeBuilding {
    public static let artifactID = "qualification-release-envelope"
    public static let artifactRelativePath = "qualification/release-envelope.json"

    private let decisionPacketValidator: any FlowRunDecisionPacketValidating
    private let loader: any FlowRunLedgerLoading
    private let persistence: any FlowArtifactPersisting
    private let currentDate: Date

    public init(
        decisionPacketValidator: any FlowRunDecisionPacketValidating,
        loader: any FlowRunLedgerLoading,
        persistence: any FlowArtifactPersisting,
        currentDate: Date = Date()
    ) {
        self.decisionPacketValidator = decisionPacketValidator
        self.loader = loader
        self.persistence = persistence
        self.currentDate = currentDate
    }

    public func buildReleaseEnvelope(
        runID: String,
        workspaceID: FlowWorkspaceID,
        maxEvidenceAgeDays: Int? = 30
    ) async throws -> FlowRunReleaseEnvelopeBuildResult {
        let validation = try await decisionPacketValidator.validateDecisionPacket(
            runID: runID,
            workspaceID: workspaceID
        )
        let ledgerResult = await loadRunLedger(runID: runID, workspaceID: workspaceID)
        let requirements = await releaseRequirements(
            runID: runID,
            workspaceID: workspaceID,
            decisionPacketValidation: validation,
            retainedArtifacts: ledgerResult.retainedArtifacts,
            maxEvidenceAgeDays: maxEvidenceAgeDays
        )
        let diagnostics = releaseDiagnostics(
            decisionPacketValidation: validation,
            requirements: requirements,
            manifestDiagnostic: ledgerResult.diagnostic
        )
        let envelope = FlowRunReleaseEnvelope(
            envelopeID: "release-envelope-\(runID)",
            runID: runID,
            status: status(requirements: requirements, diagnostics: diagnostics),
            decisionPacketValidation: validation,
            requirements: requirements,
            diagnostics: diagnostics,
            replayActions: replayActions(runID: runID)
        )
        let artifact = try await persist(envelope, runID: runID, workspaceID: workspaceID)
        return FlowRunReleaseEnvelopeBuildResult(envelope: envelope, artifact: artifact)
    }

    private func loadRunLedger(
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async -> (retainedArtifacts: [ArtifactReference]?, diagnostic: FlowDiagnostic?) {
        do {
            let ledger = try await loader.loadRunLedger(
                runID: runID
            )
            return (ledger.artifacts + ledger.actions.flatMap(\.outputs), nil)
        } catch {
            return (
                nil,
                FlowDiagnostic(
                    severity: .error,
                    code: "release-envelope-run-manifest-unreadable",
                    message: "Run manifest could not be loaded before release envelope creation: \(error.localizedDescription)"
                )
            )
        }
    }

    private func releaseRequirements(
        runID: String,
        workspaceID: FlowWorkspaceID,
        decisionPacketValidation: FlowRunDecisionPacketValidationResult,
        retainedArtifacts: [ArtifactReference]?,
        maxEvidenceAgeDays: Int?
    ) async -> [FlowRunReleaseEnvelope.Requirement] {
        let corpus = await retainedArtifactRequirement(
                requirementID: "retained-corpus-history",
                title: "Retained corpus history",
                artifactID: "qualification-corpus-history",
                relativePath: "qualification/corpus-history.json",
                purpose: "Prove capability claims across retained benchmark and corpus runs.",
                missingDiagnosticCode: "release-envelope-corpus-history-missing",
                ageDiagnosticPrefix: "release-envelope-corpus-history",
                runID: runID,
                workspaceID: workspaceID,
                retainedArtifacts: retainedArtifacts,
                maxEvidenceAgeDays: maxEvidenceAgeDays
            )
        let performance = await retainedArtifactRequirement(
                requirementID: "performance-envelope",
                title: "Performance envelope",
                artifactID: "qualification-performance-envelope",
                relativePath: "qualification/performance-envelope.json",
                purpose: "Prove runtime and scale budgets before release qualification.",
                missingDiagnosticCode: "release-envelope-performance-envelope-missing",
                ageDiagnosticPrefix: "release-envelope-performance-envelope",
                runID: runID,
                workspaceID: workspaceID,
                retainedArtifacts: retainedArtifacts,
                maxEvidenceAgeDays: maxEvidenceAgeDays
            )
        let contract = await retainedArtifactRequirement(
                requirementID: "contract-audit",
                title: "Contract audit",
                artifactID: "qualification-contract-audit",
                relativePath: "qualification/contract-audit.json",
                purpose: "Prove current schema and artifact conformance for release review and resume.",
                missingDiagnosticCode: "release-envelope-contract-audit-missing",
                ageDiagnosticPrefix: "release-envelope-contract-audit",
                runID: runID,
                workspaceID: workspaceID,
                retainedArtifacts: retainedArtifacts,
                maxEvidenceAgeDays: maxEvidenceAgeDays
            )
        let qualification = await retainedArtifactRequirement(
                requirementID: "release-qualification",
                title: "Release qualification result",
                artifactID: "release-qualification-result",
                relativePath: "stages/release.qualification/raw/result.json",
                purpose: "Prove that retained corpus, oracle correlation, process scope, and promotion gates passed for this run.",
                missingDiagnosticCode: "release-envelope-release-qualification-missing",
                ageDiagnosticPrefix: "release-envelope-release-qualification",
                runID: runID,
                workspaceID: workspaceID,
                retainedArtifacts: retainedArtifacts,
                maxEvidenceAgeDays: maxEvidenceAgeDays
            )
        let retention = await retainedArtifactRequirement(
                requirementID: "retention-index",
                title: "Retention index",
                artifactID: "qualification-retention-index",
                relativePath: "qualification/retention-index.json",
                purpose: "Prove immutable, append-only CI history and the minimum retention window.",
                missingDiagnosticCode: "release-envelope-retention-index-missing",
                ageDiagnosticPrefix: "release-envelope-retention-index",
                runID: runID,
                workspaceID: workspaceID,
                retainedArtifacts: retainedArtifacts,
                maxEvidenceAgeDays: maxEvidenceAgeDays
            )
        return [
            decisionPacketValidationRequirement(decisionPacketValidation),
            corpus,
            performance,
            contract,
            qualification,
            retention,
        ]
    }

    private func decisionPacketValidationRequirement(
        _ validation: FlowRunDecisionPacketValidationResult
    ) -> FlowRunReleaseEnvelope.Requirement {
        FlowRunReleaseEnvelope.Requirement(
            requirementID: "decision-packet-validation",
            title: "Decision packet validation",
            required: true,
            status: releaseStatus(for: validation.status),
            purpose: "Prove the review decision packet is readable, internally consistent, and integrity-checked.",
            artifactIDs: [DefaultFlowRunDecisionPacketValidator.artifactID],
            artifactPaths: [validation.validationArtifactPath].compactMap { $0 },
            artifactIntegrity: [validation.packetArtifactIntegrity].compactMap { $0 },
            diagnosticCodes: validation.diagnostics.map(\.code).sorted()
        )
    }

    private func retainedArtifactRequirement(
        requirementID: String,
        title: String,
        artifactID: String,
        relativePath: String,
        purpose: String,
        missingDiagnosticCode: String,
        ageDiagnosticPrefix: String,
        runID: String,
        workspaceID: FlowWorkspaceID,
        retainedArtifacts: [ArtifactReference]?,
        maxEvidenceAgeDays: Int?
    ) async -> FlowRunReleaseEnvelope.Requirement {
        let path = "runs/\(runID)/\(relativePath)"
        let reference = retainedArtifacts?.last { reference in
            reference.artifactID == artifactID
        }
        guard let reference else {
            return FlowRunReleaseEnvelope.Requirement(
                requirementID: requirementID,
                title: title,
                required: true,
                status: .blocked,
                purpose: purpose,
                artifactIDs: [artifactID],
                artifactPaths: [path],
                diagnosticCodes: [missingDiagnosticCode]
            )
        }

        let integrity: FlowArtifactIntegrityRecord
        do {
            _ = try await persistence.loadArtifactContent(for: reference)
            integrity = FlowArtifactIntegrityRecord(
                status: .verified,
                path: reference.locator.location.value,
                expectedSHA256: reference.digest.hexadecimalValue,
                actualSHA256: reference.digest.hexadecimalValue,
                expectedByteCount: reference.byteCount,
                actualByteCount: reference.byteCount,
                message: "Artifact content was verified by the injected persistence boundary."
            )
        } catch {
            integrity = FlowArtifactIntegrityRecord(
                status: .unreadableArtifact,
                path: reference.locator.location.value,
                expectedSHA256: reference.digest.hexadecimalValue,
                expectedByteCount: reference.byteCount,
                message: error.localizedDescription
            )
        }
        guard integrity.status == .verified else {
            return FlowRunReleaseEnvelope.Requirement(
                requirementID: requirementID,
                title: title,
                required: true,
                status: .blocked,
                purpose: purpose,
                artifactIDs: [artifactID],
                artifactPaths: [reference.path],
                artifactIntegrity: [integrity],
                diagnosticCodes: ["\(missingDiagnosticCode)-integrity-\(integrity.status.rawValue)"]
            )
        }
        if let ageDiagnosticCode = await evidenceAgeDiagnosticCode(
            artifactID: artifactID,
            reference: reference,
            workspaceID: workspaceID,
            maxEvidenceAgeDays: maxEvidenceAgeDays,
            diagnosticPrefix: ageDiagnosticPrefix
        ) {
            return FlowRunReleaseEnvelope.Requirement(
                requirementID: requirementID,
                title: title,
                required: true,
                status: .blocked,
                purpose: purpose,
                artifactIDs: [artifactID],
                artifactPaths: [reference.path],
                artifactIntegrity: [integrity],
                diagnosticCodes: [ageDiagnosticCode]
            )
        }
        let contentDiagnosticCodes = await releaseArtifactContentDiagnosticCodes(
            artifactID: artifactID,
            reference: reference,
            workspaceID: workspaceID,
            runID: runID
        )
        if !contentDiagnosticCodes.isEmpty {
            return FlowRunReleaseEnvelope.Requirement(
                requirementID: requirementID,
                title: title,
                required: true,
                status: .blocked,
                purpose: purpose,
                artifactIDs: [artifactID],
                artifactPaths: [reference.path],
                artifactIntegrity: [integrity],
                diagnosticCodes: contentDiagnosticCodes
            )
        }
        return FlowRunReleaseEnvelope.Requirement(
            requirementID: requirementID,
            title: title,
            required: true,
            status: .passed,
            purpose: purpose,
            artifactIDs: [artifactID],
            artifactPaths: [reference.path],
            artifactIntegrity: [integrity]
        )
    }

    private func releaseArtifactContentDiagnosticCodes(
        artifactID: String,
        reference: ArtifactReference,
        workspaceID: FlowWorkspaceID,
        runID: String
    ) async -> [String] {
        switch artifactID {
        case "qualification-corpus-history":
            await corpusHistoryDiagnosticCodes(reference: reference, workspaceID: workspaceID)
        case "qualification-performance-envelope":
            await performanceEnvelopeDiagnosticCodes(reference: reference, workspaceID: workspaceID)
        case "qualification-contract-audit":
            await contractAuditDiagnosticCodes(reference: reference, workspaceID: workspaceID)
        case "release-qualification-result":
            await releaseQualificationDiagnosticCodes(reference: reference, workspaceID: workspaceID, runID: runID)
        case "qualification-retention-index":
            await retentionIndexDiagnosticCodes(reference: reference, workspaceID: workspaceID, runID: runID, maxEvidenceAgeDays: nil)
        default:
            []
        }
    }

    private func corpusHistoryDiagnosticCodes(
        reference: ArtifactReference,
        workspaceID: FlowWorkspaceID
    ) async -> [String] {
        let countCodes = await corpusCountDiagnosticCodes(reference: reference)
        if !countCodes.isEmpty {
            return countCodes
        }
        let artifact: FlowRunReleaseCorpusHistory
        do {
            artifact = try await decodeArtifact(
                FlowRunReleaseCorpusHistory.self,
                reference: reference,
                workspaceID: workspaceID
            )
        } catch {
            return ["release-envelope-corpus-history-unreadable"]
        }

        var codes = Set<String>()
        if let dashboardStatus = artifact.dashboardStatus {
            if dashboardStatus != "passed" {
                codes.insert("release-envelope-corpus-dashboard-not-passed")
            }
        } else {
            codes.insert("release-envelope-corpus-dashboard-status-missing")
        }

        if let historyStatus = artifact.historyStatus {
            if historyStatus != "passed" {
                codes.insert("release-envelope-corpus-history-not-passed")
            }
        } else {
            codes.insert("release-envelope-corpus-history-status-missing")
        }

        if let retainedStatus = artifact.retainedSignoffSuiteStatus {
            if retainedStatus != "passed" {
                codes.insert("release-envelope-corpus-retained-signoff-suite-not-passed")
            }
        } else {
            codes.insert("release-envelope-corpus-retained-signoff-suite-status-missing")
        }

        if artifact.previousEntryCount <= 0 {
            codes.insert("release-envelope-corpus-previous-history-missing")
        }

        if let appended = artifact.appended {
            if !appended {
                codes.insert("release-envelope-corpus-history-not-appended")
            }
        } else {
            codes.insert("release-envelope-corpus-history-appended-missing")
        }

        if !artifact.diagnostics.isEmpty {
            codes.insert("release-envelope-corpus-diagnostics-present")
        }

        guard !artifact.domains.isEmpty else {
            codes.insert("release-envelope-corpus-domains-missing")
            return codes.sorted()
        }

        for domain in artifact.domains {
            if let domainStatus = domain.status, domainStatus != "passed" {
                codes.insert("release-envelope-corpus-domain-failed")
            }
            if domain.qualified != true {
                codes.insert("release-envelope-corpus-domain-unqualified")
            }
            if let caseCount = domain.caseCount, caseCount <= 0 {
                codes.insert("release-envelope-corpus-domain-case-count-missing")
            } else if domain.caseCount == nil {
                codes.insert("release-envelope-corpus-domain-case-count-missing")
            }
            if let passRate = domain.passRate, passRate < 1 {
                codes.insert("release-envelope-corpus-domain-pass-rate-below-one")
            }
            if let coverageTagCount = domain.coverageTagCount, coverageTagCount <= 0 {
                codes.insert("release-envelope-corpus-domain-coverage-missing")
            } else if domain.coverageTagCount == nil {
                codes.insert("release-envelope-corpus-domain-coverage-missing")
            }
            if domain.failureCount > 0 {
                codes.insert("release-envelope-corpus-domain-failures")
            }
        }
        return codes.sorted()
    }

    private func performanceEnvelopeDiagnosticCodes(
        reference: ArtifactReference,
        workspaceID: FlowWorkspaceID
    ) async -> [String] {
        let countCodes = await performanceCountDiagnosticCodes(reference: reference)
        if !countCodes.isEmpty {
            return countCodes
        }
        let artifact: FlowRunReleasePerformanceEnvelope
        do {
            artifact = try await decodeArtifact(
                FlowRunReleasePerformanceEnvelope.self,
                reference: reference,
                workspaceID: workspaceID
            )
        } catch {
            return ["release-envelope-performance-envelope-unreadable"]
        }

        var codes = Set<String>()
        let historyStatus = artifact.historyStatus
        if let historyStatus {
            if historyStatus != "passed" {
                codes.insert("release-envelope-performance-history-failed")
            }
        } else {
            codes.insert("release-envelope-performance-history-status-missing")
        }

        let promotionStatus = artifact.promotionStatus
        if let promotionStatus {
            if promotionStatus != "passed" {
                codes.insert("release-envelope-performance-promotion-failed")
            }
        } else {
            codes.insert("release-envelope-performance-promotion-status-missing")
        }

        if artifact.promotionFailureCount > 0 {
            codes.insert("release-envelope-performance-promotion-failures")
        }

        let maxTotalDurationRegression = artifact.maxTotalDurationRegression
        guard !artifact.domains.isEmpty else {
            codes.insert("release-envelope-performance-domains-missing")
            return codes.sorted()
        }

        for domain in artifact.domains {
            let domainStatus = domain.status
            if let domainStatus, domainStatus != "passed" {
                codes.insert("release-envelope-performance-domain-failed")
            }
            if domain.failureCount > 0 {
                codes.insert("release-envelope-performance-domain-failures")
            }
            if let current = domain.currentTotalDurationSeconds,
               let maximum = domain.maxAllowedTotalDurationSeconds,
               current > maximum {
                codes.insert("release-envelope-performance-duration-budget-exceeded")
            }
            if let ratio = domain.durationRegressionRatio,
               let maximum = maxTotalDurationRegression,
               ratio > maximum {
                codes.insert("release-envelope-performance-regression-budget-exceeded")
            }
            if maxTotalDurationRegression == nil && domain.maxAllowedTotalDurationSeconds == nil {
                codes.insert("release-envelope-performance-domain-budget-missing")
            }
        }
        return codes.sorted()
    }

    private func contractAuditDiagnosticCodes(
        reference: ArtifactReference,
        workspaceID: FlowWorkspaceID
    ) async -> [String] {
        let countCodes = await contractCountDiagnosticCodes(reference: reference)
        if !countCodes.isEmpty {
            return countCodes
        }
        let artifact: FlowRunReleaseContractAudit
        do {
            artifact = try await decodeArtifact(
                FlowRunReleaseContractAudit.self,
                reference: reference,
                workspaceID: workspaceID
            )
        } catch {
            return ["release-envelope-contract-audit-unreadable"]
        }

        var codes = Set<String>()
        if artifact.status != "passed" {
            codes.insert("release-envelope-contract-audit-not-passed")
        }

        if artifact.contractCount <= 0 {
            codes.insert("release-envelope-contract-audit-contract-count-missing")
        }

        if artifact.failedContractCount > 0 {
            codes.insert("release-envelope-contract-audit-failed-contracts")
        }

        if !artifact.diagnostics.isEmpty {
            codes.insert("release-envelope-contract-audit-diagnostics-present")
        }

        guard !artifact.contracts.isEmpty else {
            codes.insert("release-envelope-contract-audit-contracts-missing")
            return codes.sorted()
        }

        for contract in artifact.contracts {
            if contract.status != "passed" {
                codes.insert("release-envelope-contract-audit-contract-failed")
            }
            if contract.requiredPathCount <= 0 {
                codes.insert("release-envelope-contract-audit-contract-required-paths-missing")
            }
            if contract.failureCount > 0 {
                codes.insert("release-envelope-contract-audit-contract-failures")
            }
        }
        return codes.sorted()
    }

    private func corpusCountDiagnosticCodes(reference: ArtifactReference) async -> [String] {
        do {
            let content = try await persistence.loadArtifactContent(for: reference)
            let document = try JSONDecoder().decode(CorpusCountDocument.self, from: content)
            var codes: Set<String> = []
            if !isWholeNumber(document.previousEntryCount) {
                codes.insert("release-envelope-corpus-previous-history-count-invalid")
            }
            for domain in document.domains {
                if let value = domain.caseCount, !isWholeNumber(value) {
                    codes.insert("release-envelope-corpus-domain-case-count-invalid")
                }
                if let value = domain.coverageTagCount, !isWholeNumber(value) {
                    codes.insert("release-envelope-corpus-domain-coverage-count-invalid")
                }
                if !isWholeNumber(domain.failureCount) {
                    codes.insert("release-envelope-corpus-domain-failure-count-invalid")
                }
            }
            return codes.sorted()
        } catch {
            return []
        }
    }

    private func performanceCountDiagnosticCodes(reference: ArtifactReference) async -> [String] {
        do {
            let content = try await persistence.loadArtifactContent(for: reference)
            let document = try JSONDecoder().decode(PerformanceCountDocument.self, from: content)
            var codes: Set<String> = []
            if !isWholeNumber(document.promotionFailureCount) {
                codes.insert("release-envelope-performance-promotion-failure-count-invalid")
            }
            if document.domains.contains(where: { !isWholeNumber($0.failureCount) }) {
                codes.insert("release-envelope-performance-domain-failure-count-invalid")
            }
            return codes.sorted()
        } catch {
            return []
        }
    }

    private func contractCountDiagnosticCodes(reference: ArtifactReference) async -> [String] {
        do {
            let content = try await persistence.loadArtifactContent(for: reference)
            let document = try JSONDecoder().decode(ContractCountDocument.self, from: content)
            var codes: Set<String> = []
            if !isWholeNumber(document.contractCount) {
                codes.insert("release-envelope-contract-audit-contract-count-invalid")
            }
            if !isWholeNumber(document.failedContractCount) {
                codes.insert("release-envelope-contract-audit-failed-contract-count-invalid")
            }
            if document.contracts.contains(where: { !isWholeNumber($0.requiredPathCount) }) {
                codes.insert("release-envelope-contract-audit-contract-required-path-count-invalid")
            }
            if document.contracts.contains(where: { !isWholeNumber($0.failureCount) }) {
                codes.insert("release-envelope-contract-audit-contract-failure-count-invalid")
            }
            return codes.sorted()
        } catch {
            return []
        }
    }

    private func isWholeNumber(_ value: Double) -> Bool {
        value.isFinite && value.rounded(.towardZero) == value
    }

    private func releaseQualificationDiagnosticCodes(
        reference: ArtifactReference,
        workspaceID: FlowWorkspaceID,
        runID: String
    ) async -> [String] {
        let artifact: FlowRunReleaseQualificationArtifact
        do {
            artifact = try await decodeArtifact(
                FlowRunReleaseQualificationArtifact.self,
                reference: reference,
                workspaceID: workspaceID
            )
        } catch {
            return ["release-envelope-release-qualification-unreadable"]
        }

        var codes = Set<String>()
        if let observedRunID = artifact.runID, !runID.isEmpty,
           observedRunID != runID {
            codes.insert("release-envelope-release-qualification-run-id-mismatch")
        } else if artifact.runID == nil {
            codes.insert("release-envelope-release-qualification-run-id-missing")
        }
        if artifact.status != "completed" {
            codes.insert("release-envelope-release-qualification-not-completed")
        }

        guard let payload = artifact.payload else {
            codes.insert("release-envelope-release-qualification-payload-missing")
            return codes.sorted()
        }
        if !payload.qualified {
            codes.insert("release-envelope-release-qualification-not-qualified")
        }
        if let promotionStatus = payload.promotionStatus {
            if promotionStatus == "blocked" {
                codes.insert("release-envelope-release-qualification-promotion-blocked")
            }
        } else {
            codes.insert("release-envelope-release-qualification-promotion-status-missing")
        }
        if let digest = payload.qualificationDigest, digest.isEmpty {
            codes.insert("release-envelope-release-qualification-digest-missing")
        } else if payload.qualificationDigest == nil {
            codes.insert("release-envelope-release-qualification-digest-missing")
        }
        if let promotionFailures = payload.promotionFailureCodes, !promotionFailures.isEmpty {
            codes.insert("release-envelope-release-qualification-promotion-failures")
        }
        if let blockedLanes = payload.blockedLanes, !blockedLanes.isEmpty {
            codes.insert("release-envelope-release-qualification-blocked-lanes")
        }
        if let failedLanes = payload.failedLanes, !failedLanes.isEmpty {
            codes.insert("release-envelope-release-qualification-failed-lanes")
        }
        if payload.qualificationScope == nil {
            codes.insert("release-envelope-release-qualification-scope-missing")
        } else if let scope = payload.qualificationScope,
                  [scope.implementationID, scope.binaryDigest, scope.algorithmVersion, scope.processProfileID, scope.deckDigest]
                    .contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            codes.insert("release-envelope-release-qualification-scope-incomplete")
        }
        guard let lanes = payload.laneResults, !lanes.isEmpty else {
            codes.insert("release-envelope-release-qualification-lanes-missing")
            return codes.sorted()
        }
        for lane in lanes {
            if lane.status != "passed" {
                codes.insert("release-envelope-release-qualification-lane-failed")
            }
            if !lane.qualified {
                codes.insert("release-envelope-release-qualification-lane-unqualified")
            }
            if !lane.failureCodes.isEmpty {
                codes.insert("release-envelope-release-qualification-lane-failures")
            }
        }
        if let diagnostics = artifact.diagnostics {
            for diagnostic in diagnostics {
                if diagnostic.severity == "error" {
                    codes.insert("release-envelope-release-qualification-diagnostics-present")
                }
            }
        }
        return codes.sorted()
    }

    private func retentionIndexDiagnosticCodes(
        reference: ArtifactReference,
        workspaceID: FlowWorkspaceID,
        runID: String,
        maxEvidenceAgeDays: Int?
    ) async -> [String] {
        do {
            let index = try await decodeArtifact(
                FlowRunReleaseRetentionIndex.self,
                reference: reference,
                workspaceID: workspaceID
            )
            let maximumAgeSeconds = maxEvidenceAgeDays.map { Double($0) * 24 * 60 * 60 }
            let validation = try await DefaultFlowRunReleaseRetentionIndexValidator(
                persistence: persistence
            ).validate(
                index: index,
                runID: runID,
                workspaceID: workspaceID,
                currentDate: currentDate,
                maximumAgeSeconds: maximumAgeSeconds
            )
            return validation.diagnostics.map(\.code).sorted()
        } catch {
            return ["release-envelope-retention-index-unreadable"]
        }
    }

    private func evidenceAgeDiagnosticCode(
        artifactID: String,
        reference: ArtifactReference,
        workspaceID: FlowWorkspaceID,
        maxEvidenceAgeDays: Int?,
        diagnosticPrefix: String
    ) async -> String? {
        guard let maxEvidenceAgeDays else {
            return nil
        }
        guard maxEvidenceAgeDays >= 0 else {
            return "\(diagnosticPrefix)-age-policy-invalid"
        }
        let collectedAt: String?
        do {
            switch artifactID {
            case "qualification-corpus-history":
                collectedAt = try await decodeArtifact(EvidenceTimestampDocument.self, reference: reference, workspaceID: workspaceID).collectedAt
            case "qualification-performance-envelope":
                collectedAt = try await decodeArtifact(EvidenceTimestampDocument.self, reference: reference, workspaceID: workspaceID).collectedAt
            case "qualification-contract-audit":
                collectedAt = try await decodeArtifact(EvidenceTimestampDocument.self, reference: reference, workspaceID: workspaceID).collectedAt
            case "release-qualification-result":
                collectedAt = try await decodeArtifact(
                    FlowRunReleaseQualificationArtifact.self,
                    reference: reference,
                    workspaceID: workspaceID
                ).metadata?.completedAt
            case "qualification-retention-index":
                collectedAt = try await decodeArtifact(FlowRunReleaseRetentionIndex.self, reference: reference, workspaceID: workspaceID).recordedAt
            default:
                collectedAt = nil
            }
        } catch {
            return "\(diagnosticPrefix)-collected-at-unreadable"
        }
        guard let collectedAt else {
            return "\(diagnosticPrefix)-collected-at-missing"
        }
        guard let collectedDate = parseISO8601Date(collectedAt) else {
            return "\(diagnosticPrefix)-collected-at-invalid"
        }
        let age = currentDate.timeIntervalSince(collectedDate)
        guard age >= 0 else {
            return "\(diagnosticPrefix)-collected-at-in-future"
        }
        let maximumAge = Double(maxEvidenceAgeDays) * 24 * 60 * 60
        guard age <= maximumAge else {
            return "\(diagnosticPrefix)-stale"
        }
        return nil
    }

    private func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func releaseDiagnostics(
        decisionPacketValidation: FlowRunDecisionPacketValidationResult,
        requirements: [FlowRunReleaseEnvelope.Requirement],
        manifestDiagnostic: FlowDiagnostic?
    ) -> [FlowDiagnostic] {
        var diagnostics = decisionPacketValidation.diagnostics
        if let manifestDiagnostic {
            diagnostics.append(manifestDiagnostic)
        }
        var observedCodes = Set(diagnostics.map(\.code))
        diagnostics.append(contentsOf: requirements.flatMap { requirement in
            requirement.diagnosticCodes.compactMap { code in
                guard observedCodes.insert(code).inserted else {
                    return nil
                }
                return FlowDiagnostic(
                    severity: requirement.status == .blocked ? .error : .warning,
                    code: code,
                    message: "Release envelope requirement is \(requirement.status.rawValue): \(requirement.title)"
                )
            }
        })
        return diagnostics.sorted { left, right in
            if left.severity != right.severity {
                return severityRank(left.severity) > severityRank(right.severity)
            }
            return left.code < right.code
        }
    }

    private func status(
        requirements: [FlowRunReleaseEnvelope.Requirement],
        diagnostics: [FlowDiagnostic]
    ) -> FlowRunReleaseEnvelope.Status {
        if requirements.contains(where: { $0.required && $0.status == .blocked })
            || diagnostics.contains(where: { $0.severity == .error }) {
            return .blocked
        }
        if requirements.contains(where: { $0.status == .needsReview })
            || diagnostics.contains(where: { $0.severity == .warning }) {
            return .needsReview
        }
        return .passed
    }

    private func releaseStatus(
        for validationStatus: FlowRunDecisionPacketValidationResult.Status
    ) -> FlowRunReleaseEnvelope.Status {
        switch validationStatus {
        case .passed:
            .passed
        case .needsReview:
            .needsReview
        case .blocked:
            .blocked
        }
    }

    private func replayActions(
        runID: String
    ) -> [FlowRunSuggestedAction] {
        [
            FlowRunSuggestedAction(
                id: "validate-decision-packet",
                readiness: .ready,
                operation: .validateDecisionPacket,
                runID: runID,
                reason: "Rebuild the decision packet validation used by this release envelope."
            ),
            FlowRunSuggestedAction(
                id: "build-release-envelope",
                readiness: .ready,
                operation: .buildReleaseEnvelope,
                runID: runID,
                reason: "Rebuild the release qualification envelope from current run artifacts."
            ),
        ]
    }

    private func persist(
        _ envelope: FlowRunReleaseEnvelope,
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws -> ArtifactReference {
        let projectRelativePath = "runs/\(runID)/\(Self.artifactRelativePath)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await persistence.persistArtifact(
            content: encoder.encode(envelope),
            id: ArtifactID(rawValue: Self.artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: projectRelativePath),
                role: .output,
                kind: .report,
                format: .json
            ),
            runID: runID,
            mode: .replaceable
        )
    }

    private func decodeArtifact<Value: Decodable>(
        _ type: Value.Type,
        reference: ArtifactReference,
        workspaceID: FlowWorkspaceID
    ) async throws -> Value {
        let content = try await persistence.loadArtifactContent(
            for: reference
        )
        return try JSONDecoder().decode(type, from: content)
    }

    private func severityRank(_ severity: FlowDiagnosticSeverity) -> Int {
        switch severity {
        case .error:
            3
        case .warning:
            2
        case .info:
            1
        }
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}

private struct CorpusCountDocument: Decodable {
    struct Domain: Decodable {
        var caseCount: Double?
        var coverageTagCount: Double?
        var failureCount: Double
    }

    var previousEntryCount: Double
    var domains: [Domain]
}

private struct EvidenceTimestampDocument: Decodable {
    var collectedAt: String
}

private struct PerformanceCountDocument: Decodable {
    struct Domain: Decodable {
        var failureCount: Double
    }

    var promotionFailureCount: Double
    var domains: [Domain]
}

private struct ContractCountDocument: Decodable {
    struct Contract: Decodable {
        var requiredPathCount: Double
        var failureCount: Double
    }

    var contractCount: Double
    var failedContractCount: Double
    var contracts: [Contract]
}

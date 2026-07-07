import Foundation
import XcircuitePackage

public struct DefaultFlowRunReleaseEnvelopeBuilder: FlowRunReleaseEnvelopeBuilding {
    public static let artifactID = "qualification-release-envelope"
    public static let artifactRelativePath = "qualification/release-envelope.json"

    private let decisionPacketValidator: any FlowRunDecisionPacketValidating
    private let packageStore: XcircuitePackageStore
    private let fileReferenceVerifier: XcircuiteFileReferenceVerifier
    private let currentDate: Date

    public init(
        decisionPacketValidator: any FlowRunDecisionPacketValidating = DefaultFlowRunDecisionPacketValidator(),
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier(),
        currentDate: Date = Date()
    ) {
        self.decisionPacketValidator = decisionPacketValidator
        self.packageStore = packageStore
        self.fileReferenceVerifier = fileReferenceVerifier
        self.currentDate = currentDate
    }

    public func buildReleaseEnvelope(
        runID: String,
        projectRoot: URL,
        maxEvidenceAgeDays: Int? = 30
    ) throws -> FlowRunReleaseEnvelopeBuildResult {
        let validation = try decisionPacketValidator.validateDecisionPacket(
            runID: runID,
            projectRoot: projectRoot
        )
        let manifestResult = loadRunManifest(runID: runID, projectRoot: projectRoot)
        let requirements = releaseRequirements(
            runID: runID,
            projectRoot: projectRoot,
            decisionPacketValidation: validation,
            manifest: manifestResult.manifest,
            maxEvidenceAgeDays: maxEvidenceAgeDays
        )
        let diagnostics = releaseDiagnostics(
            decisionPacketValidation: validation,
            requirements: requirements,
            manifestDiagnostic: manifestResult.diagnostic
        )
        let envelope = FlowRunReleaseEnvelope(
            envelopeID: "release-envelope-\(runID)",
            runID: runID,
            status: status(requirements: requirements, diagnostics: diagnostics),
            decisionPacketValidation: validation,
            requirements: requirements,
            diagnostics: diagnostics,
            replayCommands: replayCommands(runID: runID, projectRoot: projectRoot)
        )
        let artifact = try persist(envelope, runID: runID, projectRoot: projectRoot)
        return FlowRunReleaseEnvelopeBuildResult(envelope: envelope, artifact: artifact)
    }

    private func loadRunManifest(
        runID: String,
        projectRoot: URL
    ) -> (manifest: XcircuiteRunManifest?, diagnostic: FlowDiagnostic?) {
        do {
            let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
            let manifest = try packageStore.readJSON(
                XcircuiteRunManifest.self,
                from: runDirectory.appending(path: "manifest.json")
            )
            return (manifest, nil)
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
        projectRoot: URL,
        decisionPacketValidation: FlowRunDecisionPacketValidationResult,
        manifest: XcircuiteRunManifest?,
        maxEvidenceAgeDays: Int?
    ) -> [FlowRunReleaseEnvelope.Requirement] {
        [
            decisionPacketValidationRequirement(decisionPacketValidation),
            retainedArtifactRequirement(
                requirementID: "retained-corpus-history",
                title: "Retained corpus history",
                artifactID: "qualification-corpus-history",
                relativePath: "qualification/corpus-history.json",
                purpose: "Prove capability claims across retained benchmark and corpus runs.",
                missingDiagnosticCode: "release-envelope-corpus-history-missing",
                ageDiagnosticPrefix: "release-envelope-corpus-history",
                runID: runID,
                projectRoot: projectRoot,
                manifest: manifest,
                maxEvidenceAgeDays: maxEvidenceAgeDays
            ),
            retainedArtifactRequirement(
                requirementID: "performance-envelope",
                title: "Performance envelope",
                artifactID: "qualification-performance-envelope",
                relativePath: "qualification/performance-envelope.json",
                purpose: "Prove runtime and scale budgets before release qualification.",
                missingDiagnosticCode: "release-envelope-performance-envelope-missing",
                ageDiagnosticPrefix: "release-envelope-performance-envelope",
                runID: runID,
                projectRoot: projectRoot,
                manifest: manifest,
                maxEvidenceAgeDays: maxEvidenceAgeDays
            ),
            retainedArtifactRequirement(
                requirementID: "migration-audit",
                title: "Migration audit",
                artifactID: "qualification-migration-audit",
                relativePath: "qualification/migration-audit.json",
                purpose: "Prove schema and artifact compatibility for release review and resume.",
                missingDiagnosticCode: "release-envelope-migration-audit-missing",
                ageDiagnosticPrefix: "release-envelope-migration-audit",
                runID: runID,
                projectRoot: projectRoot,
                manifest: manifest,
                maxEvidenceAgeDays: maxEvidenceAgeDays
            ),
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
        projectRoot: URL,
        manifest: XcircuiteRunManifest?,
        maxEvidenceAgeDays: Int?
    ) -> FlowRunReleaseEnvelope.Requirement {
        let path = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(relativePath)"
        let reference = manifest?.artifacts.first { reference in
            reference.artifactID == artifactID && reference.path == path
        }
        if reference == nil,
           let mismatchedReference = manifest?.artifacts.first(where: { reference in
               reference.artifactID == artifactID || reference.path == path
           }) {
            return FlowRunReleaseEnvelope.Requirement(
                requirementID: requirementID,
                title: title,
                required: true,
                status: .blocked,
                purpose: purpose,
                artifactIDs: uniqueSorted([artifactID, mismatchedReference.artifactID].compactMap { $0 }),
                artifactPaths: uniqueSorted([path, mismatchedReference.path]),
                diagnosticCodes: ["\(ageDiagnosticPrefix)-reference-mismatch"]
            )
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

        let integrity = fileReferenceVerifier.verify(reference, projectRoot: projectRoot)
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
        if let ageDiagnosticCode = evidenceAgeDiagnosticCode(
            reference: reference,
            projectRoot: projectRoot,
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
        let contentDiagnosticCodes = releaseArtifactContentDiagnosticCodes(
            artifactID: artifactID,
            reference: reference,
            projectRoot: projectRoot
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
        reference: XcircuiteFileReference,
        projectRoot: URL
    ) -> [String] {
        switch artifactID {
        case "qualification-corpus-history":
            corpusHistoryDiagnosticCodes(reference: reference, projectRoot: projectRoot)
        case "qualification-performance-envelope":
            performanceEnvelopeDiagnosticCodes(reference: reference, projectRoot: projectRoot)
        case "qualification-migration-audit":
            migrationAuditDiagnosticCodes(reference: reference, projectRoot: projectRoot)
        default:
            []
        }
    }

    private func corpusHistoryDiagnosticCodes(
        reference: XcircuiteFileReference,
        projectRoot: URL
    ) -> [String] {
        guard let artifactURL = fileReferenceVerifier.resolvedURL(for: reference, projectRoot: projectRoot) else {
            return ["release-envelope-corpus-history-path-invalid"]
        }
        let artifactValue: XcircuiteJSONValue
        do {
            artifactValue = try packageStore.readJSON(XcircuiteJSONValue.self, from: artifactURL)
        } catch {
            return ["release-envelope-corpus-history-unreadable"]
        }

        var codes = Set<String>()
        if let dashboardStatus = stringValue(value(at: ["dashboardStatus"], in: artifactValue)) {
            if dashboardStatus != "passed" {
                codes.insert("release-envelope-corpus-dashboard-not-passed")
            }
        } else {
            codes.insert("release-envelope-corpus-dashboard-status-missing")
        }

        if let historyStatus = stringValue(value(at: ["historyStatus"], in: artifactValue)) {
            if historyStatus != "passed" {
                codes.insert("release-envelope-corpus-history-not-passed")
            }
        } else {
            codes.insert("release-envelope-corpus-history-status-missing")
        }

        if let retainedStatus = stringValue(value(at: ["retainedSignoffSuiteStatus"], in: artifactValue)) {
            if retainedStatus != "passed" {
                codes.insert("release-envelope-corpus-retained-signoff-suite-not-passed")
            }
        } else {
            codes.insert("release-envelope-corpus-retained-signoff-suite-status-missing")
        }

        if let previousEntryCount = integerValue(
            value(at: ["previousEntryCount"], in: artifactValue),
            missingCode: "release-envelope-corpus-previous-history-missing",
            invalidCode: "release-envelope-corpus-previous-history-count-invalid",
            codes: &codes
        ) {
            if previousEntryCount <= 0 {
                codes.insert("release-envelope-corpus-previous-history-missing")
            }
        }

        if let appended = boolValue(value(at: ["appended"], in: artifactValue)) {
            if !appended {
                codes.insert("release-envelope-corpus-history-not-appended")
            }
        } else {
            codes.insert("release-envelope-corpus-history-appended-missing")
        }

        if let diagnostics = arrayValue(value(at: ["diagnostics"], in: artifactValue)), !diagnostics.isEmpty {
            codes.insert("release-envelope-corpus-diagnostics-present")
        }

        guard let domains = arrayValue(value(at: ["domains"], in: artifactValue)), !domains.isEmpty else {
            codes.insert("release-envelope-corpus-domains-missing")
            return codes.sorted()
        }

        for domainValue in domains {
            guard case .object(let domain) = domainValue else {
                codes.insert("release-envelope-corpus-domain-unreadable")
                continue
            }
            if let domainStatus = stringValue(domain["status"]), domainStatus != "passed" {
                codes.insert("release-envelope-corpus-domain-failed")
            }
            if boolValue(domain["qualified"]) != true {
                codes.insert("release-envelope-corpus-domain-unqualified")
            }
            if let caseCount = integerValue(
                domain["caseCount"],
                missingCode: "release-envelope-corpus-domain-case-count-missing",
                invalidCode: "release-envelope-corpus-domain-case-count-invalid",
                codes: &codes
            ) {
                if caseCount <= 0 {
                    codes.insert("release-envelope-corpus-domain-case-count-missing")
                }
            }
            if let passRate = numberValue(domain["passRate"]), passRate < 1 {
                codes.insert("release-envelope-corpus-domain-pass-rate-below-one")
            }
            if let coverageTagCount = integerValue(
                domain["coverageTagCount"],
                missingCode: "release-envelope-corpus-domain-coverage-missing",
                invalidCode: "release-envelope-corpus-domain-coverage-count-invalid",
                codes: &codes
            ) {
                if coverageTagCount <= 0 {
                    codes.insert("release-envelope-corpus-domain-coverage-missing")
                }
            }
            if let failureCount = integerValue(
                domain["failureCount"],
                missingCode: "release-envelope-corpus-domain-failure-count-missing",
                invalidCode: "release-envelope-corpus-domain-failure-count-invalid",
                codes: &codes
            ), failureCount > 0 {
                codes.insert("release-envelope-corpus-domain-failures")
            }
        }
        return codes.sorted()
    }

    private func performanceEnvelopeDiagnosticCodes(
        reference: XcircuiteFileReference,
        projectRoot: URL
    ) -> [String] {
        guard let artifactURL = fileReferenceVerifier.resolvedURL(for: reference, projectRoot: projectRoot) else {
            return ["release-envelope-performance-envelope-path-invalid"]
        }
        let artifactValue: XcircuiteJSONValue
        do {
            artifactValue = try packageStore.readJSON(XcircuiteJSONValue.self, from: artifactURL)
        } catch {
            return ["release-envelope-performance-envelope-unreadable"]
        }

        var codes = Set<String>()
        let historyStatus = stringValue(value(at: ["historyStatus"], in: artifactValue))
        if let historyStatus {
            if historyStatus != "passed" {
                codes.insert("release-envelope-performance-history-failed")
            }
        } else {
            codes.insert("release-envelope-performance-history-status-missing")
        }

        let promotionStatus = stringValue(value(at: ["promotionStatus"], in: artifactValue))
        if let promotionStatus {
            if promotionStatus != "passed" {
                codes.insert("release-envelope-performance-promotion-failed")
            }
        } else {
            codes.insert("release-envelope-performance-promotion-status-missing")
        }

        if let promotionFailureCount = integerValue(
            value(at: ["promotionFailureCount"], in: artifactValue),
            missingCode: "release-envelope-performance-promotion-failure-count-missing",
            invalidCode: "release-envelope-performance-promotion-failure-count-invalid",
            codes: &codes
        ) {
            if promotionFailureCount > 0 {
                codes.insert("release-envelope-performance-promotion-failures")
            }
        }

        let maxTotalDurationRegression = numberValue(value(at: ["maxTotalDurationRegression"], in: artifactValue))
        guard let domains = arrayValue(value(at: ["domains"], in: artifactValue)), !domains.isEmpty else {
            codes.insert("release-envelope-performance-domains-missing")
            return codes.sorted()
        }

        for domainValue in domains {
            guard case .object(let domain) = domainValue else {
                codes.insert("release-envelope-performance-domain-unreadable")
                continue
            }
            let domainStatus = stringValue(domain["status"])
            if let domainStatus, domainStatus != "passed" {
                codes.insert("release-envelope-performance-domain-failed")
            }
            if let failureCount = integerValue(
                domain["failureCount"],
                missingCode: "release-envelope-performance-domain-failure-count-missing",
                invalidCode: "release-envelope-performance-domain-failure-count-invalid",
                codes: &codes
            ), failureCount > 0 {
                codes.insert("release-envelope-performance-domain-failures")
            }
            if let current = numberValue(domain["currentTotalDurationSeconds"]),
               let maximum = numberValue(domain["maxAllowedTotalDurationSeconds"]),
               current > maximum {
                codes.insert("release-envelope-performance-duration-budget-exceeded")
            }
            if let ratio = numberValue(domain["durationRegressionRatio"]),
               let maximum = maxTotalDurationRegression,
               ratio > maximum {
                codes.insert("release-envelope-performance-regression-budget-exceeded")
            }
            if maxTotalDurationRegression == nil && numberValue(domain["maxAllowedTotalDurationSeconds"]) == nil {
                codes.insert("release-envelope-performance-domain-budget-missing")
            }
        }
        return codes.sorted()
    }

    private func migrationAuditDiagnosticCodes(
        reference: XcircuiteFileReference,
        projectRoot: URL
    ) -> [String] {
        guard let artifactURL = fileReferenceVerifier.resolvedURL(for: reference, projectRoot: projectRoot) else {
            return ["release-envelope-migration-audit-path-invalid"]
        }
        let artifactValue: XcircuiteJSONValue
        do {
            artifactValue = try packageStore.readJSON(XcircuiteJSONValue.self, from: artifactURL)
        } catch {
            return ["release-envelope-migration-audit-unreadable"]
        }

        var codes = Set<String>()
        if let status = stringValue(value(at: ["status"], in: artifactValue)) {
            if status != "passed" {
                codes.insert("release-envelope-migration-audit-not-passed")
            }
        } else {
            codes.insert("release-envelope-migration-audit-status-missing")
        }

        if let contractCount = integerValue(
            value(at: ["contractCount"], in: artifactValue),
            missingCode: "release-envelope-migration-audit-contract-count-missing",
            invalidCode: "release-envelope-migration-audit-contract-count-invalid",
            codes: &codes
        ) {
            if contractCount <= 0 {
                codes.insert("release-envelope-migration-audit-contract-count-missing")
            }
        }

        if let failedContractCount = integerValue(
            value(at: ["failedContractCount"], in: artifactValue),
            missingCode: "release-envelope-migration-audit-failed-contract-count-missing",
            invalidCode: "release-envelope-migration-audit-failed-contract-count-invalid",
            codes: &codes
        ) {
            if failedContractCount > 0 {
                codes.insert("release-envelope-migration-audit-failed-contracts")
            }
        }

        if let diagnostics = arrayValue(value(at: ["diagnostics"], in: artifactValue)), !diagnostics.isEmpty {
            codes.insert("release-envelope-migration-audit-diagnostics-present")
        }

        guard let contracts = arrayValue(value(at: ["contracts"], in: artifactValue)), !contracts.isEmpty else {
            codes.insert("release-envelope-migration-audit-contracts-missing")
            return codes.sorted()
        }

        for contractValue in contracts {
            guard case .object(let contract) = contractValue else {
                codes.insert("release-envelope-migration-audit-contract-unreadable")
                continue
            }
            if let status = stringValue(contract["status"]), status != "passed" {
                codes.insert("release-envelope-migration-audit-contract-failed")
            }
            if let requiredPathCount = integerValue(
                contract["requiredPathCount"],
                missingCode: "release-envelope-migration-audit-contract-required-paths-missing",
                invalidCode: "release-envelope-migration-audit-contract-required-path-count-invalid",
                codes: &codes
            ) {
                if requiredPathCount <= 0 {
                    codes.insert("release-envelope-migration-audit-contract-required-paths-missing")
                }
            }
            if let failureCount = integerValue(
                contract["failureCount"],
                missingCode: "release-envelope-migration-audit-contract-failure-count-missing",
                invalidCode: "release-envelope-migration-audit-contract-failure-count-invalid",
                codes: &codes
            ), failureCount > 0 {
                codes.insert("release-envelope-migration-audit-contract-failures")
            }
        }
        return codes.sorted()
    }

    private func evidenceAgeDiagnosticCode(
        reference: XcircuiteFileReference,
        projectRoot: URL,
        maxEvidenceAgeDays: Int?,
        diagnosticPrefix: String
    ) -> String? {
        guard let maxEvidenceAgeDays else {
            return nil
        }
        guard maxEvidenceAgeDays >= 0 else {
            return "\(diagnosticPrefix)-age-policy-invalid"
        }
        guard let artifactURL = fileReferenceVerifier.resolvedURL(for: reference, projectRoot: projectRoot) else {
            return "\(diagnosticPrefix)-path-invalid"
        }
        let artifactValue: XcircuiteJSONValue
        do {
            artifactValue = try packageStore.readJSON(XcircuiteJSONValue.self, from: artifactURL)
        } catch {
            return "\(diagnosticPrefix)-collected-at-unreadable"
        }
        guard let collectedAt = stringValue(value(at: ["collectedAt"], in: artifactValue)) else {
            return "\(diagnosticPrefix)-collected-at-missing"
        }
        guard let collectedDate = ISO8601DateFormatter().date(from: collectedAt) else {
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

    private func replayCommands(
        runID: String,
        projectRoot: URL
    ) -> [FlowRunSuggestedCommand] {
        [
            FlowRunSuggestedCommand(
                commandID: "validate-decision-packet",
                readiness: .ready,
                executable: "design-flow",
                arguments: [
                    "validate-decision-packet",
                    "--project-root",
                    projectRoot.path(percentEncoded: false),
                    "--run-id",
                    runID,
                ],
                reason: "Rebuild the decision packet validation used by this release envelope."
            ),
            FlowRunSuggestedCommand(
                commandID: "build-release-envelope",
                readiness: .ready,
                executable: "design-flow",
                arguments: [
                    "build-release-envelope",
                    "--project-root",
                    projectRoot.path(percentEncoded: false),
                    "--run-id",
                    runID,
                ],
                reason: "Rebuild the release qualification envelope from current run artifacts."
            ),
        ]
    }

    private func persist(
        _ envelope: FlowRunReleaseEnvelope,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let qualificationDirectory = runDirectory.appending(path: "qualification")
        try packageStore.ensureDirectory(at: qualificationDirectory)
        let envelopeURL = qualificationDirectory.appending(path: "release-envelope.json")
        try packageStore.writeJSON(envelope, to: envelopeURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.artifactRelativePath)"
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.artifactID,
            kind: .report,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        do {
            try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        } catch {
            guard envelope.diagnostics.contains(where: { $0.code == "release-envelope-run-manifest-unreadable" }) else {
                throw error
            }
        }
        return reference
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

    private func value(
        at path: [String],
        in value: XcircuiteJSONValue?
    ) -> XcircuiteJSONValue? {
        var current = value
        for segment in path {
            guard case .object(let object) = current else {
                return nil
            }
            current = object[segment]
        }
        return current
    }

    private func stringValue(_ value: XcircuiteJSONValue?) -> String? {
        guard case .string(let string) = value else {
            return nil
        }
        return string
    }

    private func numberValue(_ value: XcircuiteJSONValue?) -> Double? {
        guard case .number(let number) = value else {
            return nil
        }
        return number
    }

    private func integerValue(
        _ value: XcircuiteJSONValue?,
        missingCode: String,
        invalidCode: String,
        codes: inout Set<String>
    ) -> Int? {
        guard let number = numberValue(value) else {
            codes.insert(missingCode)
            return nil
        }
        guard number.isFinite,
              number.rounded(.towardZero) == number,
              number >= Double(Int.min),
              number <= Double(Int.max) else {
            codes.insert(invalidCode)
            return nil
        }
        return Int(number)
    }

    private func boolValue(_ value: XcircuiteJSONValue?) -> Bool? {
        guard case .bool(let bool) = value else {
            return nil
        }
        return bool
    }

    private func arrayValue(_ value: XcircuiteJSONValue?) -> [XcircuiteJSONValue]? {
        guard case .array(let array) = value else {
            return nil
        }
        return array
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}

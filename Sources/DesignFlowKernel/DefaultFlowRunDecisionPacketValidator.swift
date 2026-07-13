import Foundation

public struct DefaultFlowRunDecisionPacketValidator: FlowRunDecisionPacketValidating {
    public static let artifactID = "review-decision-packet-validation"
    public static let artifactRelativePath = "review/decision-packet-validation.json"

    private let packageStore: XcircuitePackageStore
    private let fileReferenceVerifier: XcircuiteFileReferenceVerifier
    private let reviewBundler: any FlowRunReviewBundling

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier(),
        reviewBundler: any FlowRunReviewBundling = DefaultFlowRunReviewBundler()
    ) {
        self.packageStore = packageStore
        self.fileReferenceVerifier = fileReferenceVerifier
        self.reviewBundler = reviewBundler
    }

    public func validateDecisionPacket(
        runID: String,
        projectRoot: URL
    ) throws -> FlowRunDecisionPacketValidationResult {
        let packetPath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(DefaultFlowRunDecisionPacketBuilder.artifactRelativePath)"
        var result = makeValidationResult(
            runID: runID,
            projectRoot: projectRoot,
            packetPath: packetPath
        )
        result.validationArtifactPath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(Self.artifactRelativePath)"
        try persist(result, runID: runID, projectRoot: projectRoot)
        return result
    }

    private func makeValidationResult(
        runID: String,
        projectRoot: URL,
        packetPath: String
    ) -> FlowRunDecisionPacketValidationResult {
        let manifest: XcircuiteRunManifest
        do {
            manifest = try packageStore.loadRunManifest(
                runID: runID,
                inProjectAt: projectRoot
            )
        } catch {
            return blockedResult(
                runID: runID,
                packetPath: packetPath,
                diagnostics: [
                    FlowDiagnostic(
                        severity: .error,
                        code: "decision-packet-run-manifest-unreadable",
                        message: "Run manifest could not be loaded before decision packet validation: \(error.localizedDescription)"
                    ),
                ]
            )
        }

        let packetReference = manifest.artifacts.first { reference in
            reference.artifactID == DefaultFlowRunDecisionPacketBuilder.artifactID
                && reference.path == packetPath
        }
        let mismatchedPacketReference = packetReference == nil
            ? manifest.artifacts.first { reference in
                reference.artifactID == DefaultFlowRunDecisionPacketBuilder.artifactID
                    || reference.path == packetPath
            }
            : nil
        let packetIntegrity = packetReference.map {
            fileReferenceVerifier.verify($0, projectRoot: projectRoot)
        }
        var diagnostics: [FlowDiagnostic] = []
        if let mismatchedPacketReference {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-artifact-reference-mismatch",
                    message: "Run manifest decision packet reference must match both artifactID and path: \(mismatchedPacketReference.path)"
                )
            )
        } else if packetReference == nil {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-artifact-reference-missing",
                    message: "Run manifest does not register review/decision-packet.json."
                )
            )
        }
        if let packetIntegrity, packetIntegrity.status != .verified {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-artifact-integrity-\(packetIntegrity.status.rawValue)",
                    message: packetIntegrity.message
                )
            )
        }

        let packet: FlowRunDecisionPacket
        do {
            packet = try packageStore.readJSON(
                FlowRunDecisionPacket.self,
                from: projectRoot.appending(path: packetPath)
            )
        } catch {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-unreadable",
                    message: "Decision packet could not be decoded: \(error.localizedDescription)"
                )
            )
            return FlowRunDecisionPacketValidationResult(
                runID: runID,
                packetPath: packetPath,
                status: .blocked,
                packetArtifactIntegrity: packetIntegrity,
                diagnostics: diagnostics
            )
        }

        diagnostics.append(contentsOf: contentDiagnostics(packet: packet, expectedRunID: runID))
        diagnostics.append(contentsOf: currentStateDiagnostics(
            packet: packet,
            runID: runID,
            projectRoot: projectRoot
        ))
        return validationResult(
            runID: runID,
            packetPath: packetPath,
            packet: packet,
            packetIntegrity: packetIntegrity,
            diagnostics: diagnostics
        )
    }

    private func contentDiagnostics(
        packet: FlowRunDecisionPacket,
        expectedRunID: String
    ) -> [FlowDiagnostic] {
        var diagnostics: [FlowDiagnostic] = []
        if packet.schemaVersion != 1 {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-schema-version-unsupported",
                    message: "Decision packet schemaVersion must be 1."
                )
            )
        }
        if packet.runID != expectedRunID {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-run-id-mismatch",
                    message: "Decision packet runID does not match the validated run."
                )
            )
        }
        if packet.reviewBundle.runID != expectedRunID {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-review-bundle-run-id-mismatch",
                    message: "Decision packet review bundle runID does not match the validated run."
                )
            )
        }
        diagnostics.append(contentsOf: artifactRequirementDiagnostics(packet.requiredArtifacts))
        diagnostics.append(contentsOf: completionIssueDiagnostics(packet.completionIssues))
        if !packet.replayCommands.contains(where: { $0.commandID == "review-run" && $0.readiness == .ready }) {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-review-replay-command-missing",
                    message: "Decision packet must include a ready review-run replay command."
                )
            )
        }
        let expectedReadiness = expectedReadiness(for: packet.completionIssues)
        if packet.readiness != expectedReadiness {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-readiness-inconsistent",
                    message: "Decision packet readiness \(packet.readiness.rawValue) does not match completion issues; expected \(expectedReadiness.rawValue)."
                )
            )
        }
        return diagnostics
    }

    private func currentStateDiagnostics(
        packet: FlowRunDecisionPacket,
        runID: String,
        projectRoot: URL
    ) -> [FlowDiagnostic] {
        let currentPacket: FlowRunDecisionPacket
        do {
            let currentBundle = try reviewBundler.makeReviewBundle(
                runID: runID,
                projectRoot: projectRoot
            )
            currentPacket = DefaultFlowRunDecisionPacketBuilder()
                .makePacket(from: currentBundle, projectRoot: projectRoot)
        } catch {
            return [
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-current-review-bundle-unreadable",
                    message: "Current review bundle could not be rebuilt during decision packet validation: \(error.localizedDescription)"
                ),
            ]
        }

        var diagnostics: [FlowDiagnostic] = []
        if packet.status != currentPacket.status {
            diagnostics.append(staleDiagnostic(
                code: "decision-packet-stale-run-status",
                message: "Decision packet run status no longer matches the current run ledger."
            ))
        }
        if packet.readiness != currentPacket.readiness {
            diagnostics.append(staleDiagnostic(
                code: "decision-packet-stale-readiness",
                message: "Decision packet readiness no longer matches the current run ledger."
            ))
        }
        if packet.reviewBundle.summary != currentPacket.reviewBundle.summary {
            diagnostics.append(staleDiagnostic(
                code: "decision-packet-stale-summary",
                message: "Decision packet summary no longer matches the current run ledger."
            ))
        }
        if packet.reviewBundle.reviewItems != currentPacket.reviewBundle.reviewItems {
            diagnostics.append(staleDiagnostic(
                code: "decision-packet-stale-review-items",
                message: "Decision packet review items no longer match the current run ledger."
            ))
        }
        if packet.reviewBundle.approvals != currentPacket.reviewBundle.approvals {
            diagnostics.append(staleDiagnostic(
                code: "decision-packet-stale-approvals",
                message: "Decision packet approvals no longer match the current run ledger."
            ))
        }
        if packet.reviewBundle.decisionActions != currentPacket.reviewBundle.decisionActions {
            diagnostics.append(staleDiagnostic(
                code: "decision-packet-stale-decision-actions",
                message: "Decision packet decision actions no longer match the current run ledger."
            ))
        }
        if packet.requiredArtifacts != currentPacket.requiredArtifacts {
            diagnostics.append(staleDiagnostic(
                code: "decision-packet-stale-required-artifacts",
                message: "Decision packet required artifact status no longer matches the current run ledger."
            ))
        }
        if packet.unresolvedReviewItems != currentPacket.unresolvedReviewItems {
            diagnostics.append(staleDiagnostic(
                code: "decision-packet-stale-unresolved-review-items",
                message: "Decision packet unresolved review items no longer match the current run ledger."
            ))
        }
        if packet.completionIssues != currentPacket.completionIssues {
            diagnostics.append(staleDiagnostic(
                code: "decision-packet-stale-completion-issues",
                message: "Decision packet completion issues no longer match the current run ledger."
            ))
        }
        if packet.replayCommands != currentPacket.replayCommands {
            diagnostics.append(staleDiagnostic(
                code: "decision-packet-stale-replay-commands",
                message: "Decision packet replay commands no longer match the current run ledger."
            ))
        }
        return diagnostics
    }

    private func staleDiagnostic(code: String, message: String) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: .error,
            code: code,
            message: message
        )
    }

    private func expectedReadiness(
        for issues: [FlowRunDecisionPacket.CompletionIssue]
    ) -> FlowRunDecisionPacket.Readiness {
        guard !issues.isEmpty else {
            return .ready
        }
        if issues.contains(where: { $0.severity == .error }) {
            return .blocked
        }
        return .needsReview
    }

    private func artifactRequirementDiagnostics(
        _ requirements: [FlowRunDecisionPacket.ArtifactRequirement]
    ) -> [FlowDiagnostic] {
        requirements.compactMap { requirement in
            guard requirement.required else {
                return nil
            }
            switch requirement.status {
            case .satisfied:
                return nil
            case .missing:
                return FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-required-artifact-missing",
                    message: "Required decision packet artifact is missing: \(requirement.role)"
                )
            case .invalid:
                return FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-required-artifact-invalid",
                    message: "Required decision packet artifact failed integrity: \(requirement.role)"
                )
            case .notRequired:
                return FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-required-artifact-status-invalid",
                    message: "Required decision packet artifact cannot be marked notRequired: \(requirement.role)"
                )
            }
        }
    }

    private func completionIssueDiagnostics(
        _ issues: [FlowRunDecisionPacket.CompletionIssue]
    ) -> [FlowDiagnostic] {
        issues.map { issue in
            FlowDiagnostic(
                severity: issue.severity,
                code: "decision-packet-\(issue.code)",
                message: issue.message
            )
        }
    }

    private func validationResult(
        runID: String,
        packetPath: String,
        packet: FlowRunDecisionPacket,
        packetIntegrity: XcircuiteFileReferenceIntegrity?,
        diagnostics: [FlowDiagnostic]
    ) -> FlowRunDecisionPacketValidationResult {
        let requiredArtifacts = packet.requiredArtifacts.filter(\.required)
        return FlowRunDecisionPacketValidationResult(
            runID: runID,
            packetPath: packetPath,
            status: status(for: diagnostics),
            packetReadiness: packet.readiness,
            packetArtifactIntegrity: packetIntegrity,
            requiredArtifactCount: requiredArtifacts.count,
            satisfiedRequiredArtifactCount: requiredArtifacts.filter { $0.status == .satisfied }.count,
            missingRequiredArtifactCount: requiredArtifacts.filter { $0.status == .missing }.count,
            invalidRequiredArtifactCount: requiredArtifacts.filter { $0.status == .invalid }.count,
            unresolvedReviewItemCount: packet.unresolvedReviewItems.count,
            completionIssueCount: packet.completionIssues.count,
            replayCommandCount: packet.replayCommands.count,
            diagnostics: diagnostics
        )
    }

    private func status(
        for diagnostics: [FlowDiagnostic]
    ) -> FlowRunDecisionPacketValidationResult.Status {
        if diagnostics.contains(where: { $0.severity == .error }) {
            return .blocked
        }
        if diagnostics.contains(where: { $0.severity == .warning }) {
            return .needsReview
        }
        return .passed
    }

    private func blockedResult(
        runID: String,
        packetPath: String,
        diagnostics: [FlowDiagnostic]
    ) -> FlowRunDecisionPacketValidationResult {
        FlowRunDecisionPacketValidationResult(
            runID: runID,
            packetPath: packetPath,
            status: .blocked,
            diagnostics: diagnostics
        )
    }

    private func persist(
        _ result: FlowRunDecisionPacketValidationResult,
        runID: String,
        projectRoot: URL
    ) throws {
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let reviewDirectory = runDirectory.appending(path: "review")
        try packageStore.ensureDirectory(at: reviewDirectory)
        let validationURL = reviewDirectory.appending(path: "decision-packet-validation.json")
        try packageStore.writeJSON(result, to: validationURL, forProjectAt: projectRoot)

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
            guard result.diagnostics.contains(where: { $0.code == "decision-packet-run-manifest-unreadable" }) else {
                throw error
            }
        }
    }
}

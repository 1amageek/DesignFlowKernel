import CircuiteFoundation
import Foundation

public struct DefaultFlowRunDecisionPacketValidator: FlowRunDecisionPacketValidating {
    public static let artifactID = "review-decision-packet-validation"
    public static let artifactRelativePath = "review/decision-packet-validation.json"

    private let loader: any FlowRunLedgerLoading
    private let persistence: any FlowArtifactPersisting
    private let reviewBundler: any FlowRunReviewBundling
    private let artifactLocationValidator: any FlowRunArtifactLocationValidator

    public init(
        loader: any FlowRunLedgerLoading,
        persistence: any FlowArtifactPersisting,
        reviewBundler: any FlowRunReviewBundling,
        artifactLocationValidator: any FlowRunArtifactLocationValidator = DefaultFlowRunArtifactLocationValidator()
    ) {
        self.loader = loader
        self.persistence = persistence
        self.reviewBundler = reviewBundler
        self.artifactLocationValidator = artifactLocationValidator
    }

    public func validateDecisionPacket(
        runID: String,
        workspaceID: FlowWorkspaceID
    ) async throws -> FlowRunDecisionPacketValidationResult {
        let packetPath = "runs/\(runID)/\(DefaultFlowRunDecisionPacketBuilder.artifactRelativePath)"
        var result = await makeValidationResult(
            runID: runID,
            workspaceID: workspaceID,
            packetPath: packetPath
        )
        result.validationArtifactPath = "runs/\(runID)/\(Self.artifactRelativePath)"
        try await persist(result, runID: runID, workspaceID: workspaceID)
        return result
    }

    private func makeValidationResult(
        runID: String,
        workspaceID: FlowWorkspaceID,
        packetPath: String
    ) async -> FlowRunDecisionPacketValidationResult {
        let ledger: FlowRunLedger
        do {
            ledger = try await loader.loadRunLedger(
                runID: runID
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

        let retainedArtifacts = ledger.artifacts + ledger.actions.flatMap(\.outputs)
        let packetCandidates = retainedArtifacts.filter { reference in
            reference.artifactID == DefaultFlowRunDecisionPacketBuilder.artifactID
        }
        let matchingPacketReferences = packetCandidates.filter { reference in
            reference.locator.role == .output
                && reference.locator.kind == .report
                && reference.locator.format == .json
                && artifactLocationValidator.isReference(
                    reference,
                    boundTo: packetPath,
                    allowingContentAddressedVariant: true
                )
        }
        let packetReference = packetCandidates.count == 1
            ? matchingPacketReferences.first
            : nil
        let mismatchedPacketReference = packetReference == nil ? packetCandidates.last : nil
        let resolvedPacketPath = packetReference?.path ?? packetPath
        let packetIntegrity: FlowArtifactIntegrityRecord?
        if let packetReference {
            do {
                _ = try await persistence.loadArtifactContent(for: packetReference)
                packetIntegrity = FlowArtifactIntegrityRecord(
                    status: .verified,
                    path: packetReference.locator.location.value,
                    expectedSHA256: packetReference.digest.hexadecimalValue,
                    actualSHA256: packetReference.digest.hexadecimalValue,
                    expectedByteCount: packetReference.byteCount,
                    actualByteCount: packetReference.byteCount,
                    message: "Artifact content was verified by the injected persistence boundary."
                )
            } catch {
                packetIntegrity = FlowArtifactIntegrityRecord(
                    status: .unreadableArtifact,
                    path: packetReference.locator.location.value,
                    expectedSHA256: packetReference.digest.hexadecimalValue,
                    expectedByteCount: packetReference.byteCount,
                    message: error.localizedDescription
                )
            }
        } else {
            packetIntegrity = nil
        }
        var diagnostics: [FlowDiagnostic] = []
        if let mismatchedPacketReference {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-artifact-reference-mismatch",
                    message: "The retained decision packet reference is not exactly bound to the requested run and decision-packet artifact contract: \(mismatchedPacketReference.path)"
                )
            )
        } else if packetReference == nil {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-artifact-reference-missing",
                    message: "The run ledger does not retain review/decision-packet.json."
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
            guard let packetReference else {
                throw FlowExecutionError.missingArtifact(packetPath)
            }
            let content = try await persistence.loadArtifactContent(
                for: packetReference
            )
            packet = try JSONDecoder().decode(FlowRunDecisionPacket.self, from: content)
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
                packetPath: resolvedPacketPath,
                status: .blocked,
                packetArtifactIntegrity: packetIntegrity,
                diagnostics: diagnostics
            )
        }

        diagnostics.append(contentsOf: contentDiagnostics(packet: packet, expectedRunID: runID))
        let currentState = await currentStateDiagnostics(
            packet: packet,
            runID: runID,
            workspaceID: workspaceID
        )
        diagnostics.append(contentsOf: currentState)
        return validationResult(
            runID: runID,
            packetPath: resolvedPacketPath,
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
        if packet.schemaVersion != 3 {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-schema-version-unsupported",
                    message: "Decision packet schemaVersion must be 3."
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
        if packet.reviewBundle.schemaVersion != 3 {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-review-bundle-schema-version-unsupported",
                    message: "Decision packet review bundle schemaVersion must be 3."
                )
            )
        }
        diagnostics.append(contentsOf: artifactRequirementDiagnostics(packet.requiredArtifacts))
        diagnostics.append(contentsOf: completionIssueDiagnostics(packet.completionIssues))
        if !packet.replayActions.contains(where: { $0.operation == .reviewRun && $0.readiness == .ready }) {
            diagnostics.append(
                FlowDiagnostic(
                    severity: .error,
                    code: "decision-packet-review-replay-action-missing",
                    message: "Decision packet must include a ready review-run replay action."
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
        workspaceID: FlowWorkspaceID
    ) async -> [FlowDiagnostic] {
        let currentPacket: FlowRunDecisionPacket
        do {
            let currentBundle = try await reviewBundler.makeReviewBundle(
                runID: runID,
                workspaceID: workspaceID
            )
            currentPacket = DefaultFlowRunDecisionPacketBuilder(
                reviewBundler: reviewBundler,
                persistence: persistence
            )
                .makePacket(from: currentBundle, workspaceID: workspaceID)
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
        if packet.replayActions != currentPacket.replayActions {
            diagnostics.append(staleDiagnostic(
                code: "decision-packet-stale-replay-actions",
                message: "Decision packet replay actions no longer match the current run ledger."
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
        packetIntegrity: FlowArtifactIntegrityRecord?,
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
            replayActionCount: packet.replayActions.count,
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
        workspaceID: FlowWorkspaceID
    ) async throws {
        let projectRelativePath = "runs/\(runID)/\(Self.artifactRelativePath)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            _ = try await persistence.persistArtifact(
                content: encoder.encode(result),
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
        } catch {
            guard result.diagnostics.contains(where: { $0.code == "decision-packet-run-manifest-unreadable" }) else {
                throw error
            }
        }
    }
}

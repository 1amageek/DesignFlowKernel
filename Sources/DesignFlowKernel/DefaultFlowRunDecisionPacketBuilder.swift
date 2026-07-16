import CircuiteFoundation
import Foundation

public struct DefaultFlowRunDecisionPacketBuilder: FlowRunDecisionPacketBuilding {
    public static let artifactID = "review-decision-packet"
    public static let artifactRelativePath = "review/decision-packet.json"

    private let reviewBundler: any FlowRunReviewBundling
    private let persistence: any FlowArtifactPersisting

    public init(
        reviewBundler: any FlowRunReviewBundling,
        persistence: any FlowArtifactPersisting
    ) {
        self.reviewBundler = reviewBundler
        self.persistence = persistence
    }

    public func buildDecisionPacket(
        runID: String,
        projectRoot: URL
    ) async throws -> FlowRunDecisionPacketBuildResult {
        let bundle = try await reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let packet = makePacket(from: bundle, projectRoot: projectRoot)
        let projectRelativePath = "runs/\(runID)/\(Self.artifactRelativePath)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reference = try await persistence.persistArtifact(
            content: encoder.encode(packet),
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
        return FlowRunDecisionPacketBuildResult(packet: packet, artifact: reference)
    }

    func makePacket(
        from bundle: FlowRunReviewBundle,
        projectRoot: URL
    ) -> FlowRunDecisionPacket {
        let requirements = artifactRequirements(from: bundle)
        let unresolvedItems = bundle.reviewItems.filter { item in
            item.status != .closed && item.status != .informational
        }
        let issues = completionIssues(
            requirements: requirements,
            unresolvedItems: unresolvedItems
        )
        let readiness = readiness(for: issues)
        return FlowRunDecisionPacket(
            packetID: "decision-packet-\(bundle.runID)",
            runID: bundle.runID,
            status: bundle.status,
            readiness: readiness,
            reviewBundle: bundle,
            requiredArtifacts: requirements,
            unresolvedReviewItems: unresolvedItems,
            completionIssues: issues,
            replayCommands: replayCommands(from: bundle, projectRoot: projectRoot)
        )
    }

    private func artifactRequirements(
        from bundle: FlowRunReviewBundle
    ) -> [FlowRunDecisionPacket.ArtifactRequirement] {
        let roles = Set(bundle.artifacts.map { $0.purpose.rawValue })
        let hasPlanning = roles.contains { role in
            role.hasPrefix("planning-")
        }
        let hasApprovalRecord = bundle.approvals.isEmpty == false
        let specifications: [(role: String, required: Bool, purpose: String)] = [
            ("run-manifest", true, "Preserve run identity, status, and registered artifact references."),
            ("toolchain", true, "Show selected tools, health, evidence, and trust-gate context."),
            ("stage-result", bundle.summary.stages.isEmpty == false, "Preserve per-stage status, gates, diagnostics, and produced artifacts."),
            ("stage-summary", bundle.summary.stages.isEmpty == false, "Provide compact domain summaries without requiring log scraping."),
            ("run-progress", bundle.summary.progressEventCount > 0, "Preserve progress and retry/cancellation timeline context."),
            ("action-ledger", bundle.summary.actionCount > 0, "Preserve Human, Agent, and CLI actions in execution order."),
            ("design-diff", bundle.summary.designDiff != nil, "Expose proposed or accepted design changes for review."),
            ("approval", hasApprovalRecord, "Preserve explicit human approval or rejection records."),
            ("planning-problem", hasPlanning, "Preserve the translated planning problem that created the candidate plan."),
            ("planning-candidate-plan", hasPlanning, "Preserve selected planner steps and risk classifications."),
            ("planning-plan-verification", hasPlanning, "Preserve planning correctness and post-execution verification gates."),
            ("planning-rejected-plans", roles.contains("planning-rejected-plans"), "Preserve rejected feedback for re-planning."),
        ]

        return specifications.map { specification in
            makeArtifactRequirement(
                role: specification.role,
                required: specification.required,
                purpose: specification.purpose,
                artifacts: bundle.artifacts
            )
        }
    }

    private func makeArtifactRequirement(
        role: String,
        required: Bool,
        purpose: String,
        artifacts: [FlowRunReviewArtifact]
    ) -> FlowRunDecisionPacket.ArtifactRequirement {
        let matchingArtifacts = artifacts.filter { $0.purpose.rawValue == role }
        guard required else {
            return FlowRunDecisionPacket.ArtifactRequirement(
                role: role,
                required: false,
                status: matchingArtifacts.isEmpty ? .notRequired : .satisfied,
                purpose: purpose,
                artifactPaths: matchingArtifacts.map { $0.reference.path }.sorted()
            )
        }
        guard !matchingArtifacts.isEmpty else {
            return FlowRunDecisionPacket.ArtifactRequirement(
                role: role,
                required: true,
                status: .missing,
                purpose: purpose,
                diagnosticCodes: ["decision-packet-required-artifact-missing"]
            )
        }
        let invalidArtifacts = matchingArtifacts.filter { artifact in
            artifact.integrity?.status != .verified
        }
        if invalidArtifacts.isEmpty {
            return FlowRunDecisionPacket.ArtifactRequirement(
                role: role,
                required: true,
                status: .satisfied,
                purpose: purpose,
                artifactPaths: matchingArtifacts.map { $0.reference.path }.sorted()
            )
        }
        return FlowRunDecisionPacket.ArtifactRequirement(
            role: role,
            required: true,
            status: .invalid,
            purpose: purpose,
            artifactPaths: invalidArtifacts.map { $0.reference.path }.sorted(),
            diagnosticCodes: artifactRequirementDiagnosticCodes(for: invalidArtifacts)
        )
    }

    private func artifactRequirementDiagnosticCodes(
        for artifacts: [FlowRunReviewArtifact]
    ) -> [String] {
        var codes = Set(["decision-packet-required-artifact-invalid"])
        for artifact in artifacts {
            guard let integrity = artifact.integrity else {
                codes.insert("decision-packet-required-artifact-unverified")
                continue
            }
            codes.insert("decision-packet-required-artifact-integrity-\(integrity.status.rawValue)")
        }
        return codes.sorted()
    }

    private func completionIssues(
        requirements: [FlowRunDecisionPacket.ArtifactRequirement],
        unresolvedItems: [FlowRunReviewItem]
    ) -> [FlowRunDecisionPacket.CompletionIssue] {
        let artifactIssues = requirements.compactMap { requirement -> FlowRunDecisionPacket.CompletionIssue? in
            switch requirement.status {
            case .missing:
                return FlowRunDecisionPacket.CompletionIssue(
                    code: "required-artifact-missing",
                    severity: .error,
                    message: "Required decision packet artifact role is missing: \(requirement.role)",
                    artifactRole: requirement.role,
                    artifactPaths: requirement.artifactPaths
                )
            case .invalid:
                return FlowRunDecisionPacket.CompletionIssue(
                    code: "required-artifact-invalid",
                    severity: .error,
                    message: "Required decision packet artifact role has failed integrity: \(requirement.role)",
                    artifactRole: requirement.role,
                    artifactPaths: requirement.artifactPaths
                )
            case .satisfied, .notRequired:
                return nil
            }
        }
        let reviewIssues = unresolvedItems.map { item in
            FlowRunDecisionPacket.CompletionIssue(
                code: "unresolved-review-item",
                severity: item.severity,
                message: item.reason,
                reviewItemID: item.itemID,
                nextActionID: item.nextActionID,
                artifactPaths: item.artifactPaths
            )
        }
        return (artifactIssues + reviewIssues).sorted { left, right in
            if left.severity != right.severity {
                return severityRank(left.severity) > severityRank(right.severity)
            }
            return left.code < right.code
        }
    }

    private func readiness(
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

    private func replayCommands(
        from bundle: FlowRunReviewBundle,
        projectRoot: URL
    ) -> [FlowRunSuggestedCommand] {
        let reviewCommand = FlowRunSuggestedCommand(
            commandID: "review-run",
            readiness: .ready,
            executable: "design-flow",
            arguments: [
                "review-run",
                "--project-root",
                projectRoot.path(percentEncoded: false),
                "--run-id",
                bundle.runID,
            ],
            reason: "Rebuild the review bundle used by this decision packet."
        )
        let suggestedCommands = bundle.summary.nextActions.flatMap(\.suggestedCommands)
        return ([reviewCommand] + suggestedCommands).sorted { left, right in
            left.commandID < right.commandID
        }
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
}

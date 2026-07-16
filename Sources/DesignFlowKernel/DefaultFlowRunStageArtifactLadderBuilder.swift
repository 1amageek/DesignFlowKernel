import CircuiteFoundation
import Foundation

public struct DefaultFlowRunStageArtifactLadderBuilder: FlowRunStageArtifactLadderBuilding {
    public static let artifactID = "review-stage-artifact-ladder"
    public static let artifactRelativePath = "review/stage-artifact-ladder.json"
    private static let requiredSignoffManifestRoles = [
        "generated-layout",
        "signoff-input",
        "signoff-summary",
        "post-layout-report",
        "run-manifest",
        "review-ref",
    ]

    private let loader: any FlowRunLedgerLoading
    private let reviewBundler: any FlowRunReviewBundling
    private let persistence: any FlowArtifactPersisting
    private let identifierPolicy = FlowRunReviewIdentifierPolicy()

    public init(
        loader: any FlowRunLedgerLoading,
        reviewBundler: any FlowRunReviewBundling,
        persistence: any FlowArtifactPersisting
    ) {
        self.loader = loader
        self.reviewBundler = reviewBundler
        self.persistence = persistence
    }

    public func makeStageArtifactLadder(
        runID: String,
        projectRoot: URL
    ) async throws -> FlowRunStageArtifactLadder {
        let ledger = try await loader.loadRunLedger(runID: runID)
        let bundle = try await reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        return makeStageArtifactLadder(
            from: bundle,
            stageResults: ledger.stages,
            projectRoot: projectRoot
        )
    }

    public func buildStageArtifactLadder(
        runID: String,
        projectRoot: URL
    ) async throws -> FlowRunStageArtifactLadderBuildResult {
        let ladder = try await makeStageArtifactLadder(runID: runID, projectRoot: projectRoot)
        let projectRelativePath = "runs/\(runID)/\(Self.artifactRelativePath)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reference = try await persistence.persistArtifact(
            content: encoder.encode(ladder),
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
        return FlowRunStageArtifactLadderBuildResult(ladder: ladder, artifact: reference)
    }

    public func makeStageArtifactLadder(
        from bundle: FlowRunReviewBundle,
        stageResults: [FlowStageResult],
        projectRoot: URL
    ) -> FlowRunStageArtifactLadder {
        let artifacts = bundle.artifacts
            .filter { $0.artifactID != Self.artifactID }
            .map {
                artifact(
                    from: $0,
                    statusRef: identifierPolicy.stageStatusRef(
                        runID: bundle.runID,
                        stageID: $0.stageID
                    )
                )
            }
        let stageArtifacts = artifacts.filter { $0.stageID != nil }
        let runArtifacts = artifacts.filter { $0.stageID == nil }
        let stageResultsByID = stageResultMap(from: stageResults)
        let duplicateStageResultIDs = duplicateStageIDs(in: stageResults)
        let reviewItemsByStage = Dictionary(grouping: bundle.reviewItems.filter { $0.stageID != nil }) {
            $0.stageID ?? ""
        }
        let nextActionsByStage = Dictionary(grouping: bundle.summary.nextActions.filter { $0.stageID != nil }) {
            $0.stageID ?? ""
        }
        let artifactsByStage = Dictionary(grouping: stageArtifacts) { $0.stageID ?? "" }
        let stageSummaries = bundle.summary.stages
        let stages = stageSummaries.enumerated().map { offset, stageSummary in
            let artifacts = sortedArtifacts(artifactsByStage[stageSummary.stageID, default: []])
            let stageResult = stageResultsByID[stageSummary.stageID]
            let statusRef = identifierPolicy.stageStatusRef(
                runID: bundle.runID,
                stageID: stageSummary.stageID
            )
            let nextStageID = offset + 1 < stageSummaries.count ? stageSummaries[offset + 1].stageID : nil
            return FlowRunStageArtifactLadder.Stage(
                index: offset + 1,
                stageID: stageSummary.stageID,
                status: stageSummary.status,
                gates: stageSummary.gates,
                diagnosticCodes: diagnosticCodes(
                    for: stageSummary,
                    duplicateStageResultIDs: duplicateStageResultIDs
                ),
                artifactCount: artifacts.count,
                attemptCount: stageSummary.attemptCount,
                retryCount: stageSummary.retryCount,
                category: stageCategory(for: stageSummary, artifacts: artifacts),
                statusRef: statusRef,
                domains: sortedDomains(from: artifacts),
                roleCoverage: roleCoverage(from: artifacts),
                artifacts: artifacts,
                handoffRefs: handoffRefs(
                    from: artifacts,
                    fromStageID: stageSummary.stageID,
                    toStageID: nextStageID,
                    statusRef: statusRef
                ),
                retryRefs: retryRefs(from: stageResult?.attempts ?? []),
                attempts: stageResult?.attempts ?? [],
                reviewItems: reviewItemsByStage[stageSummary.stageID, default: []].sorted(by: reviewItemSort),
                nextActions: nextActionsByStage[stageSummary.stageID, default: []].sorted(by: nextActionSort)
            )
        }
        let runReviewItems = bundle.reviewItems
            .filter { $0.stageID == nil }
            .sorted(by: reviewItemSort)
        let readiness = readiness(
            reviewItems: bundle.reviewItems,
            artifacts: artifacts,
            hasDuplicateStageResults: !duplicateStageResultIDs.isEmpty
        )
        let summary = FlowRunStageArtifactLadder.Summary(
            stageCount: stages.count,
            runArtifactCount: runArtifacts.count,
            stageArtifactCount: stageArtifacts.count,
            retryArtifactCount: artifacts.filter { $0.domain == "retry" }.count,
            reviewItemCount: bundle.reviewItems.count,
            unresolvedReviewItemCount: bundle.reviewItems.filter(isUnresolved).count,
            invalidArtifactCount: artifacts.filter(hasIntegrityIssue).count,
            artifactCoverageIssueCount: bundle.reviewItems.filter { $0.kind == .artifactCoverage }.count,
            domainCounts: domainCounts(from: artifacts),
            stageCategoryCounts: stageCategoryCounts(from: stages),
            handoffRefCount: stages.reduce(0) { partial, stage in
                partial + (stage.handoffRefs?.count ?? 0)
            },
            statusRefCount: stages.filter { $0.statusRef != nil }.count
        )
        return FlowRunStageArtifactLadder(
            runID: bundle.runID,
            status: bundle.status,
            readiness: readiness,
            summary: summary,
            runArtifacts: sortedArtifacts(runArtifacts),
            stages: stages,
            runReviewItems: runReviewItems,
            nextActions: bundle.summary.nextActions.sorted(by: nextActionSort),
            replayCommands: replayCommands(from: bundle, projectRoot: projectRoot),
            signoffManifestCoverage: signoffManifestCoverage(from: artifacts)
        )
    }

    private func artifact(
        from reviewArtifact: FlowRunReviewArtifact,
        statusRef: String?
    ) -> FlowRunStageArtifactLadder.Artifact {
        let domain = artifactDomain(for: reviewArtifact)
        return FlowRunStageArtifactLadder.Artifact(
            role: reviewArtifact.role,
            domain: domain,
            artifactID: reviewArtifact.artifactID,
            stageID: reviewArtifact.stageID,
            path: reviewArtifact.path,
            kind: reviewArtifact.kind,
            format: reviewArtifact.format,
            sha256: reviewArtifact.sha256,
            byteCount: reviewArtifact.byteCount,
            integrity: reviewArtifact.integrity,
            statusRef: statusRef,
            handoffRole: handoffRole(for: reviewArtifact, domain: domain)
        )
    }

    private func artifactDomain(for artifact: FlowRunReviewArtifact) -> String {
        if artifact.role == "stage-attempts" {
            return "retry"
        }
        if artifact.role == "design-diff" || artifact.kind == .designDiff {
            return "edit"
        }
        if artifact.role.hasPrefix("planning-") || artifact.path.contains("/planning/") {
            return "planning"
        }
        if artifact.role == "approval" || artifact.role == "stage-artifact-ladder" || artifact.path.contains("/review/") {
            return "review"
        }
        let searchable = [
            artifact.role,
            artifact.artifactID ?? "",
            artifact.stageID ?? "",
            artifact.path,
            artifact.kind.rawValue,
            artifact.format.rawValue,
        ]
        .joined(separator: " ")
        .lowercased()

        if searchable.contains("post-layout") || searchable.contains("post_layout") || searchable.contains("comparison") {
            return "postLayoutComparison"
        }
        if searchable.contains("edit") || searchable.contains("diff") {
            return "edit"
        }
        if searchable.contains("review") {
            return "review"
        }
        if searchable.contains("drc") {
            return "drc"
        }
        if searchable.contains("lvs") {
            return "lvs"
        }
        if searchable.contains("pex") || searchable.contains("spef") || artifact.kind == .parasitics || artifact.format == .spef {
            return "pex"
        }
        if searchable.contains("export") || artifact.format == .oasis || artifact.format == .gdsii
            || artifact.format == .lef || artifact.format == .def {
            return "export"
        }
        if artifact.kind == .waveform || artifact.kind == .measurement || searchable.contains("simulation") {
            return "simulation"
        }
        if artifact.kind == .layout {
            return "layout"
        }
        if artifact.kind == .netlist {
            return "netlist"
        }
        return "other"
    }

    private func signoffManifestCoverage(
        from artifacts: [FlowRunStageArtifactLadder.Artifact]
    ) -> FlowRunStageArtifactLadder.SignoffManifestCoverage {
        let eligibleArtifacts = artifacts.filter(isVerifiedArtifact)
        var pathsByRole: [String: Set<String>] = [:]
        for artifact in eligibleArtifacts {
            for role in signoffManifestRoles(for: artifact) {
                pathsByRole[role, default: []].insert(artifact.path)
            }
        }

        let requiredRoles = Self.requiredSignoffManifestRoles
        let satisfiedRoles = requiredRoles.filter {
            !(pathsByRole[$0] ?? []).isEmpty
        }
        let missingRoles = requiredRoles.filter {
            (pathsByRole[$0] ?? []).isEmpty
        }
        let unsignedPaths = unsignedRequiredArtifactPaths(
            from: artifacts,
            requiredRoles: requiredRoles
        )
        return FlowRunStageArtifactLadder.SignoffManifestCoverage(
            requiredRoles: requiredRoles,
            satisfiedRoles: satisfiedRoles,
            missingRoles: missingRoles,
            artifactPathsByRole: pathsByRole.mapValues { $0.sorted() },
            unsignedArtifactPaths: unsignedPaths,
            allRequiredArtifactsHaveHashesAndByteCounts: missingRoles.isEmpty && unsignedPaths.isEmpty
        )
    }

    private func signoffManifestRoles(
        for artifact: FlowRunStageArtifactLadder.Artifact
    ) -> Set<String> {
        var roles = Set<String>()
        let searchable = [
            artifact.role,
            artifact.domain,
            artifact.artifactID ?? "",
            artifact.path,
            artifact.kind.rawValue,
            artifact.format.rawValue,
        ]
        .joined(separator: " ")
        .lowercased()

        if artifact.role == "run-manifest" {
            roles.insert("run-manifest")
        }
        if artifact.domain == "review"
            || artifact.role == "approval"
            || artifact.role == "stage-artifact-ladder" {
            roles.insert("review-ref")
        }
        if artifact.domain == "postLayoutComparison" {
            roles.insert("post-layout-report")
        }
        if artifact.domain == "drc" || artifact.domain == "lvs" || artifact.domain == "pex" {
            roles.insert("signoff-summary")
        }
        if artifact.kind == .layout
            || artifact.format == .oasis
            || artifact.format == .gdsii
            || artifact.format == .lef
            || artifact.format == .def
            || artifact.domain == "export" {
            roles.insert("generated-layout")
            roles.insert("signoff-input")
        }
        if artifact.kind == .netlist || searchable.contains("signoff-input") {
            roles.insert("signoff-input")
        }
        return roles
    }

    private func unsignedRequiredArtifactPaths(
        from artifacts: [FlowRunStageArtifactLadder.Artifact],
        requiredRoles: [String]
    ) -> [String] {
        let requiredRoleSet = Set(requiredRoles)
        return artifacts.filter { artifact in
            !signoffManifestRoles(for: artifact).isDisjoint(with: requiredRoleSet)
                && (!isVerifiedArtifact(artifact) || artifact.sha256 == nil || artifact.byteCount == nil)
        }
        .map(\.path)
        .sorted()
    }

    private func handoffRole(for artifact: FlowRunReviewArtifact, domain: String) -> String {
        if artifact.stageID == nil {
            return "run-artifact"
        }
        if artifact.role == "stage-attempts" || domain == "retry" {
            return "retry-record"
        }
        if artifact.role == "stage-summary" {
            return "stage-status"
        }
        return "stage-output"
    }

    private func stageCategory(
        for stage: FlowRunStageSummary,
        artifacts: [FlowRunStageArtifactLadder.Artifact]
    ) -> String {
        let searchable = ([stage.stageID] + artifacts.flatMap { artifact in
            [
                artifact.role,
                artifact.domain,
                artifact.artifactID ?? "",
                artifact.path,
                artifact.kind.rawValue,
                artifact.format.rawValue,
            ]
        })
        .joined(separator: " ")
        .lowercased()

        if searchable.contains("post-layout") || searchable.contains("post_layout")
            || searchable.contains("postlayout") || searchable.contains("comparison") {
            return "postLayoutComparison"
        }
        if searchable.contains("review") || searchable.contains("approval") {
            return "review"
        }
        if searchable.contains("drc") {
            return "drc"
        }
        if searchable.contains("lvs") {
            return "lvs"
        }
        if searchable.contains("pex") || searchable.contains("spef") {
            return "pex"
        }
        if searchable.contains("export") || searchable.contains("gds") || searchable.contains("oasis")
            || searchable.contains("lef") || searchable.contains("def") {
            return "export"
        }
        if searchable.contains("edit") || searchable.contains("diff") {
            return "edit"
        }
        if searchable.contains("simulation") || searchable.contains("waveform") {
            return "simulation"
        }
        if searchable.contains("planning") {
            return "planning"
        }
        return "other"
    }

    private func handoffRefs(
        from artifacts: [FlowRunStageArtifactLadder.Artifact],
        fromStageID: String,
        toStageID: String?,
        statusRef: String?
    ) -> [FlowRunStageArtifactLadder.HandoffRef] {
        guard identifierPolicy.isValidStageID(fromStageID) else {
            return []
        }
        let safeToStageID = toStageID.flatMap {
            identifierPolicy.isValidStageID($0) ? $0 : nil
        }
        return artifacts
            .filter { $0.handoffRole != "retry-record" && isVerifiedArtifact($0) }
            .map { artifact in
                FlowRunStageArtifactLadder.HandoffRef(
                    role: artifact.handoffRole ?? "stage-output",
                    fromStageID: fromStageID,
                    toStageID: safeToStageID,
                    artifactID: artifact.artifactID,
                    artifactPath: artifact.path,
                    domain: artifact.domain,
                    statusRef: statusRef,
                    sha256: artifact.sha256,
                    byteCount: artifact.byteCount
                )
            }
            .sorted { left, right in
                if left.domain != right.domain {
                    return left.domain < right.domain
                }
                return left.artifactPath < right.artifactPath
            }
    }

    private func retryRefs(
        from attempts: [FlowStageAttemptRecord]
    ) -> [FlowRunStageArtifactLadder.RetryRef] {
        attempts
            .map { attempt in
                FlowRunStageArtifactLadder.RetryRef(
                    stageID: attempt.stageID,
                    attemptIndex: attempt.attemptIndex,
                    status: attempt.status,
                    shouldRetry: attempt.retryDecision.shouldRetry,
                    reason: attempt.retryDecision.reason,
                    diagnosticCodes: attempt.diagnosticCodes
                )
            }
            .sorted { left, right in
                left.attemptIndex < right.attemptIndex
            }
    }

    private func roleCoverage(
        from artifacts: [FlowRunStageArtifactLadder.Artifact]
    ) -> [FlowRunStageArtifactLadder.RoleCoverage] {
        Dictionary(grouping: artifacts) { $0.role }
            .map { role, roleArtifacts in
                FlowRunStageArtifactLadder.RoleCoverage(
                    role: role,
                    artifactCount: roleArtifacts.count,
                    verifiedCount: roleArtifacts.filter { $0.integrity?.status == .verified }.count,
                    issueCount: roleArtifacts.filter(hasIntegrityIssue).count,
                    artifactPaths: roleArtifacts.map(\.path).sorted()
                )
            }
            .sorted { $0.role < $1.role }
    }

    private func readiness(
        reviewItems: [FlowRunReviewItem],
        artifacts: [FlowRunStageArtifactLadder.Artifact],
        hasDuplicateStageResults: Bool
    ) -> FlowRunStageArtifactLadder.Readiness {
        let unresolvedItems = reviewItems.filter(isUnresolved)
        if hasDuplicateStageResults
            || artifacts.contains(where: hasIntegrityError)
            || unresolvedItems.contains(where: { $0.severity == .error }) {
            return .blocked
        }
        if artifacts.contains(where: hasIntegrityIssue) || !unresolvedItems.isEmpty {
            return .needsReview
        }
        return .ready
    }

    private func stageResultMap(from stageResults: [FlowStageResult]) -> [String: FlowStageResult] {
        var resultsByID: [String: FlowStageResult] = [:]
        for result in stageResults where resultsByID[result.stageID] == nil {
            resultsByID[result.stageID] = result
        }
        return resultsByID
    }

    private func duplicateStageIDs(in stageResults: [FlowStageResult]) -> Set<String> {
        var seen = Set<String>()
        var duplicates = Set<String>()
        for result in stageResults {
            if !seen.insert(result.stageID).inserted {
                duplicates.insert(result.stageID)
            }
        }
        return duplicates
    }

    private func diagnosticCodes(
        for stageSummary: FlowRunStageSummary,
        duplicateStageResultIDs: Set<String>
    ) -> [String] {
        var codes = Set(stageSummary.diagnosticCodes)
        if duplicateStageResultIDs.contains(stageSummary.stageID) {
            codes.insert("stage-artifact-ladder-duplicate-stage-result")
        }
        return codes.sorted()
    }

    private func isVerifiedArtifact(_ artifact: FlowRunStageArtifactLadder.Artifact) -> Bool {
        artifact.integrity?.status == .verified
    }

    private func hasIntegrityIssue(_ artifact: FlowRunStageArtifactLadder.Artifact) -> Bool {
        guard let status = artifact.integrity?.status else {
            return true
        }
        return status != .verified
    }

    private func hasIntegrityError(_ artifact: FlowRunStageArtifactLadder.Artifact) -> Bool {
        switch artifact.integrity?.status {
        case .missingArtifact, .invalidDigest, .invalidByteCount, .byteCountMismatch, .sha256Mismatch,
             .invalidIdentifier, .noRecordedReference, .invalidPath, .unreadableArtifact:
            return true
        case nil:
            return true
        case .missingDigest, .missingByteCount, .verified:
            return false
        }
    }

    private func isUnresolved(_ item: FlowRunReviewItem) -> Bool {
        switch item.status {
        case .needsReview, .readyToResume, .needsRepair:
            return true
        case .informational, .closed:
            return false
        }
    }

    private func domainCounts(
        from artifacts: [FlowRunStageArtifactLadder.Artifact]
    ) -> [String: Int] {
        Dictionary(grouping: artifacts) { $0.domain }
            .mapValues(\.count)
    }

    private func stageCategoryCounts(
        from stages: [FlowRunStageArtifactLadder.Stage]
    ) -> [String: Int] {
        Dictionary(grouping: stages.compactMap(\.category)) { $0 }
            .mapValues(\.count)
    }

    private func sortedDomains(
        from artifacts: [FlowRunStageArtifactLadder.Artifact]
    ) -> [String] {
        Array(Set(artifacts.map(\.domain))).sorted()
    }

    private func sortedArtifacts(
        _ artifacts: [FlowRunStageArtifactLadder.Artifact]
    ) -> [FlowRunStageArtifactLadder.Artifact] {
        artifacts.sorted { left, right in
            if left.stageID != right.stageID {
                return (left.stageID ?? "") < (right.stageID ?? "")
            }
            if left.domain != right.domain {
                return left.domain < right.domain
            }
            if left.role != right.role {
                return left.role < right.role
            }
            return left.path < right.path
        }
    }

    private func reviewItemSort(_ left: FlowRunReviewItem, _ right: FlowRunReviewItem) -> Bool {
        if severityRank(left.severity) != severityRank(right.severity) {
            return severityRank(left.severity) > severityRank(right.severity)
        }
        return left.itemID < right.itemID
    }

    private func nextActionSort(_ left: FlowRunNextAction, _ right: FlowRunNextAction) -> Bool {
        if severityRank(left.severity) != severityRank(right.severity) {
            return severityRank(left.severity) > severityRank(right.severity)
        }
        return left.actionID < right.actionID
    }

    private func replayCommands(
        from bundle: FlowRunReviewBundle,
        projectRoot: URL
    ) -> [FlowRunSuggestedCommand] {
        let runIDIsValid = identifierPolicy.isValidRunID(bundle.runID)
        let runIDArgument = runIDIsValid ? bundle.runID : "<invalid-run-id>"
        let readiness: FlowRunSuggestedCommandReadiness = runIDIsValid ? .ready : .requiresInput
        let reviewCommand = FlowRunSuggestedCommand(
            commandID: "review-run",
            readiness: readiness,
            executable: "design-flow",
            arguments: [
                "review-run",
                "--project-root",
                projectRoot.path(percentEncoded: false),
                "--run-id",
                runIDArgument,
            ],
            reason: "Rebuild the review bundle used by this stage artifact ladder."
        )
        let ladderCommand = FlowRunSuggestedCommand(
            commandID: "build-stage-artifact-ladder",
            readiness: readiness,
            executable: "design-flow",
            arguments: [
                "build-stage-artifact-ladder",
                "--project-root",
                projectRoot.path(percentEncoded: false),
                "--run-id",
                runIDArgument,
            ],
            reason: "Rebuild and persist the stage-ordered artifact ladder for this run."
        )
        let suggestedCommands = bundle.summary.nextActions.flatMap(\.suggestedCommands)
        return ([reviewCommand, ladderCommand] + suggestedCommands).sorted { left, right in
            left.commandID < right.commandID
        }
    }

    private func severityRank(_ severity: FlowDiagnosticSeverity) -> Int {
        switch severity {
        case .error:
            return 3
        case .warning:
            return 2
        case .info:
            return 1
        }
    }
}

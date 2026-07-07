import DesignFlowKernel
import Foundation
import XcircuitePackage

public enum DesignFlowCLICommand {
    public static func run(arguments: [String]) throws -> String {
        guard let command = arguments.first else {
            throw DesignFlowCLIError.usage
        }

        switch command {
        case "build-decision-packet":
            return try buildDecisionPacket(arguments: Array(arguments.dropFirst()))
        case "validate-decision-packet":
            return try validateDecisionPacket(arguments: Array(arguments.dropFirst()))
        case "collect-release-evidence":
            return try collectReleaseEvidence(arguments: Array(arguments.dropFirst()))
        case "build-release-envelope":
            return try buildReleaseEnvelope(arguments: Array(arguments.dropFirst()))
        case "approve-gate":
            return try approveGate(arguments: Array(arguments.dropFirst()))
        case "request-cancel":
            return try requestCancel(arguments: Array(arguments.dropFirst()))
        case "inspect-run":
            return try inspectRun(arguments: Array(arguments.dropFirst()))
        case "review-run":
            return try reviewRun(arguments: Array(arguments.dropFirst()))
        case "build-stage-artifact-ladder":
            return try buildStageArtifactLadder(arguments: Array(arguments.dropFirst()))
        case "progress-run":
            return try progressRunSnapshot(arguments: Array(arguments.dropFirst()))
        case "--help", "-h", "help":
            return helpText
        default:
            throw DesignFlowCLIError.unknownCommand(command)
        }
    }

    public static func runStreaming(
        arguments: [String],
        emit: @Sendable (String) async throws -> Void
    ) async throws -> String {
        guard let command = arguments.first else {
            throw DesignFlowCLIError.usage
        }

        switch command {
        case "progress-run":
            return try await progressRun(arguments: Array(arguments.dropFirst()), emit: emit)
        default:
            return try run(arguments: arguments)
        }
    }

    public static func runProcess(
        arguments: [String],
        emit: @Sendable (String) async throws -> Void = { _ in }
    ) async throws -> DesignFlowCLIExecutionResult {
        let output = try await runStreaming(arguments: arguments, emit: emit)
        return DesignFlowCLIExecutionResult(
            output: output,
            exitCode: processExitCode(for: arguments, output: output)
        )
    }

    private static func processExitCode(for arguments: [String], output: String) -> Int {
        switch arguments.first {
        case "validate-decision-packet":
            return decisionPacketValidationExitCode(output: output)
        case "build-release-envelope":
            return releaseEnvelopeExitCode(output: output)
        default:
            return 0
        }
    }

    private static func decisionPacketValidationExitCode(output: String) -> Int {
        guard let data = output.data(using: .utf8) else {
            return 1
        }
        let validation: FlowRunDecisionPacketValidationResult
        do {
            validation = try JSONDecoder().decode(
                FlowRunDecisionPacketValidationResult.self,
                from: data
            )
        } catch {
            return 1
        }
        switch validation.status {
        case .passed:
            return 0
        case .needsReview, .blocked:
            return 2
        }
    }

    private static func releaseEnvelopeExitCode(output: String) -> Int {
        guard let data = output.data(using: .utf8) else {
            return 1
        }
        let buildResult: FlowRunReleaseEnvelopeBuildResult
        do {
            buildResult = try JSONDecoder().decode(
                FlowRunReleaseEnvelopeBuildResult.self,
                from: data
            )
        } catch {
            return 1
        }
        switch buildResult.envelope.status {
        case .passed:
            return 0
        case .needsReview, .blocked:
            return 2
        }
    }

    private static func inspectRun(arguments: [String]) throws -> String {
        var parser = DesignFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return inspectRunHelpText
            default:
                throw DesignFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw DesignFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw DesignFlowCLIError.missingOption("--run-id")
        }

        let summary = try DefaultFlowRunLedgerInspector().inspectRun(
            runID: runID,
            projectRoot: projectRoot
        )
        return try encode(summary, pretty: pretty)
    }

    private static func reviewRun(arguments: [String]) throws -> String {
        var parser = DesignFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return reviewRunHelpText
            default:
                throw DesignFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw DesignFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw DesignFlowCLIError.missingOption("--run-id")
        }

        let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
            runID: runID,
            projectRoot: projectRoot
        )
        return try encode(bundle, pretty: pretty)
    }

    private static func buildStageArtifactLadder(arguments: [String]) throws -> String {
        var parser = DesignFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return buildStageArtifactLadderHelpText
            default:
                throw DesignFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw DesignFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw DesignFlowCLIError.missingOption("--run-id")
        }

        let result = try DefaultFlowRunStageArtifactLadderBuilder().buildStageArtifactLadder(
            runID: runID,
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    private static func buildDecisionPacket(arguments: [String]) throws -> String {
        var parser = DesignFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return buildDecisionPacketHelpText
            default:
                throw DesignFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw DesignFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw DesignFlowCLIError.missingOption("--run-id")
        }

        let result = try DefaultFlowRunDecisionPacketBuilder().buildDecisionPacket(
            runID: runID,
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    private static func validateDecisionPacket(arguments: [String]) throws -> String {
        var parser = DesignFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return validateDecisionPacketHelpText
            default:
                throw DesignFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw DesignFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw DesignFlowCLIError.missingOption("--run-id")
        }

        let result = try DefaultFlowRunDecisionPacketValidator().validateDecisionPacket(
            runID: runID,
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    private static func buildReleaseEnvelope(arguments: [String]) throws -> String {
        var parser = DesignFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var maxEvidenceAgeDays: Int?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--max-evidence-age-days":
                maxEvidenceAgeDays = try parseInt(
                    try parser.requiredValue(after: argument),
                    option: argument
                )
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return buildReleaseEnvelopeHelpText
            default:
                throw DesignFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw DesignFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw DesignFlowCLIError.missingOption("--run-id")
        }

        let result = try DefaultFlowRunReleaseEnvelopeBuilder().buildReleaseEnvelope(
            runID: runID,
            projectRoot: projectRoot,
            maxEvidenceAgeDays: maxEvidenceAgeDays ?? 30
        )
        return try encode(result, pretty: pretty)
    }

    private static func collectReleaseEvidence(arguments: [String]) throws -> String {
        var parser = DesignFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var signoffDashboardPath: URL?
        var migrationReportPath: URL?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--signoff-dashboard":
                signoffDashboardPath = URL(filePath: try parser.requiredValue(after: argument))
            case "--migration-report":
                migrationReportPath = URL(filePath: try parser.requiredValue(after: argument))
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return collectReleaseEvidenceHelpText
            default:
                throw DesignFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw DesignFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw DesignFlowCLIError.missingOption("--run-id")
        }
        guard let signoffDashboardPath else {
            throw DesignFlowCLIError.missingOption("--signoff-dashboard")
        }
        guard let migrationReportPath else {
            throw DesignFlowCLIError.missingOption("--migration-report")
        }

        let result = try DefaultFlowRunReleaseEvidenceCollector().collectReleaseEvidence(
            runID: runID,
            projectRoot: projectRoot,
            signoffDashboardPath: signoffDashboardPath,
            migrationReportPath: migrationReportPath
        )
        return try encode(result, pretty: pretty)
    }

    private static func progressRunSnapshot(arguments: [String]) throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return progressRunHelpText
        }
        let options = try parseProgressRunOptions(arguments: arguments)
        if options.follow {
            throw DesignFlowCLIError.invalidValue(
                option: "--follow",
                value: "true",
                expected: "use runStreaming for follow mode"
            )
        }
        if options.waitForNewEvents {
            throw DesignFlowCLIError.invalidValue(
                option: "--wait",
                value: "true",
                expected: "use runStreaming for wait mode"
            )
        }
        let snapshot = try DefaultFlowRunProgressSubscriber().snapshot(
            request: options.request
        )
        return try encode(snapshot, pretty: options.pretty)
    }

    private static func progressRun(
        arguments: [String],
        emit: @Sendable (String) async throws -> Void
    ) async throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return progressRunHelpText
        }
        let options = try parseProgressRunOptions(arguments: arguments)
        let subscriber = DefaultFlowRunProgressSubscriber()
        if options.follow {
            if options.pretty {
                throw DesignFlowCLIError.invalidValue(
                    option: "--pretty",
                    value: "true",
                    expected: "compact JSONL output when --follow is set"
                )
            }
            _ = try await subscriber.followProgress(request: options.request) { event in
                try await emit(try encode(event, pretty: false))
            }
            return ""
        }

        let snapshot: FlowRunProgressSnapshot
        if options.waitForNewEvents {
            snapshot = try await subscriber.waitForProgress(request: options.request)
        } else {
            snapshot = try subscriber.snapshot(request: options.request)
        }
        return try encode(snapshot, pretty: options.pretty)
    }

    private static func parseProgressRunOptions(arguments: [String]) throws -> ProgressRunOptions {
        var parser = DesignFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var afterSequence = 0
        var timeoutMilliseconds = 0
        var pollIntervalMilliseconds = 250
        var waitForNewEvents = false
        var follow = false
        var stopWhenRunFinished = true
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--since-sequence":
                afterSequence = try parseInt(
                    try parser.requiredValue(after: argument),
                    option: argument
                )
            case "--timeout-milliseconds":
                timeoutMilliseconds = try parseInt(
                    try parser.requiredValue(after: argument),
                    option: argument
                )
            case "--poll-interval-milliseconds":
                pollIntervalMilliseconds = try parseInt(
                    try parser.requiredValue(after: argument),
                    option: argument
                )
            case "--wait":
                waitForNewEvents = true
            case "--follow":
                follow = true
                waitForNewEvents = true
            case "--stop-when-run-finished":
                stopWhenRunFinished = true
            case "--include-terminal-history":
                stopWhenRunFinished = false
            case "--pretty":
                pretty = true
            default:
                throw DesignFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw DesignFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw DesignFlowCLIError.missingOption("--run-id")
        }

        return ProgressRunOptions(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: projectRoot,
                runID: runID,
                afterSequence: afterSequence,
                waitForNewEvents: waitForNewEvents,
                timeoutMilliseconds: timeoutMilliseconds,
                pollIntervalMilliseconds: pollIntervalMilliseconds,
                stopWhenRunFinished: stopWhenRunFinished
            ),
            follow: follow,
            waitForNewEvents: waitForNewEvents,
            pretty: pretty
        )
    }

    private static func parseInt(_ value: String, option: String) throws -> Int {
        guard let parsed = Int(value) else {
            throw DesignFlowCLIError.invalidValue(
                option: option,
                value: value,
                expected: "integer"
            )
        }
        return parsed
    }

    private static func approveGate(arguments: [String]) throws -> String {
        var parser = DesignFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var stageID: String?
        var verdict: FlowGateApprovalVerdict?
        var reviewer: String?
        var reviewerKind: XcircuiteRunActionActor.Kind = .human
        var note = ""
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--stage-id":
                stageID = try parser.requiredValue(after: argument)
            case "--verdict":
                verdict = try parseVerdict(try parser.requiredValue(after: argument))
            case "--reviewer":
                reviewer = try parser.requiredValue(after: argument)
            case "--reviewer-kind":
                reviewerKind = try parseReviewerKind(try parser.requiredValue(after: argument))
            case "--note":
                note = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return approveGateHelpText
            default:
                throw DesignFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw DesignFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw DesignFlowCLIError.missingOption("--run-id")
        }
        guard let stageID else {
            throw DesignFlowCLIError.missingOption("--stage-id")
        }
        guard let verdict else {
            throw DesignFlowCLIError.missingOption("--verdict")
        }
        guard let reviewer else {
            throw DesignFlowCLIError.missingOption("--reviewer")
        }

        let result = try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: projectRoot,
                runID: runID,
                stageID: stageID,
                verdict: verdict,
                reviewer: reviewer,
                reviewerKind: reviewerKind,
                note: note
            )
        )
        return try encode(result, pretty: pretty)
    }

    private static func parseReviewerKind(_ value: String) throws -> XcircuiteRunActionActor.Kind {
        guard let kind = XcircuiteRunActionActor.Kind(rawValue: value) else {
            throw DesignFlowCLIError.invalidValue(
                option: "--reviewer-kind",
                value: value,
                expected: "agent, human, cli, or system"
            )
        }
        return kind
    }

    private static func requestCancel(arguments: [String]) throws -> String {
        var parser = DesignFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var requestedBy: String?
        var reason = ""
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--requested-by":
                requestedBy = try parser.requiredValue(after: argument)
            case "--reason":
                reason = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return requestCancelHelpText
            default:
                throw DesignFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw DesignFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw DesignFlowCLIError.missingOption("--run-id")
        }
        guard let requestedBy else {
            throw DesignFlowCLIError.missingOption("--requested-by")
        }

        let result = try DefaultFlowRunCancellationRecorder().requestCancellation(
            projectRoot: projectRoot,
            runID: runID,
            requestedBy: requestedBy,
            reason: reason
        )
        return try encode(result, pretty: pretty)
    }

    private static func parseVerdict(_ value: String) throws -> FlowGateApprovalVerdict {
        guard let verdict = FlowGateApprovalVerdict(rawValue: value) else {
            throw DesignFlowCLIError.invalidValue(
                option: "--verdict",
                value: value,
                expected: "approved or rejected"
            )
        }
        return verdict
    }

    private static func encode<T: Encodable>(_ value: T, pretty: Bool) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw DesignFlowCLIError.encodeFailed(error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw DesignFlowCLIError.encodeFailed("JSON output was not valid UTF-8.")
        }
        return text
    }

    public static var helpText: String {
        """
        Usage:
          design-flow approve-gate --project-root <path> --run-id <id> --stage-id <id> --verdict <approved|rejected> --reviewer <id> [--note <text>] [--pretty]
          design-flow request-cancel --project-root <path> --run-id <id> --requested-by <id> [--reason <text>] [--pretty]
          design-flow inspect-run --project-root <path> --run-id <id> [--pretty]
          design-flow review-run --project-root <path> --run-id <id> [--pretty]
          design-flow build-stage-artifact-ladder --project-root <path> --run-id <id> [--pretty]
          design-flow build-decision-packet --project-root <path> --run-id <id> [--pretty]
          design-flow validate-decision-packet --project-root <path> --run-id <id> [--pretty]
          design-flow collect-release-evidence --project-root <path> --run-id <id> --signoff-dashboard <path> --migration-report <path> [--pretty]
          design-flow build-release-envelope --project-root <path> --run-id <id> [--max-evidence-age-days <days>] [--pretty]
          design-flow progress-run --project-root <path> --run-id <id> [--since-sequence <n>] [--wait|--follow] [--timeout-milliseconds <n>] [--poll-interval-milliseconds <n>] [--pretty]
          design-flow --help
        """
    }

    public static var inspectRunHelpText: String {
        """
        Usage:
          design-flow inspect-run --project-root <path> --run-id <id> [--pretty]

        Emits a machine-readable FlowRunLedgerSummary JSON document.
        """
    }

    public static var reviewRunHelpText: String {
        """
        Usage:
          design-flow review-run --project-root <path> --run-id <id> [--pretty]

        Emits a machine-readable FlowRunReviewBundle JSON document for human cockpit and Agent review.
        """
    }

    public static var buildStageArtifactLadderHelpText: String {
        """
        Usage:
          design-flow build-stage-artifact-ladder --project-root <path> --run-id <id> [--pretty]

        Writes review/stage-artifact-ladder.json and emits a FlowRunStageArtifactLadderBuildResult JSON document.
        """
    }

    public static var buildDecisionPacketHelpText: String {
        """
        Usage:
          design-flow build-decision-packet --project-root <path> --run-id <id> [--pretty]

        Writes review/decision-packet.json and emits a FlowRunDecisionPacketBuildResult JSON document.
        """
    }

    public static var validateDecisionPacketHelpText: String {
        """
        Usage:
          design-flow validate-decision-packet --project-root <path> --run-id <id> [--pretty]

        Writes review/decision-packet-validation.json and emits a FlowRunDecisionPacketValidationResult JSON document.
        """
    }

    public static var buildReleaseEnvelopeHelpText: String {
        """
        Usage:
          design-flow build-release-envelope --project-root <path> --run-id <id> [--max-evidence-age-days <days>] [--pretty]

        Writes qualification/release-envelope.json and emits a FlowRunReleaseEnvelopeBuildResult JSON document. The default evidence age gate is 30 days.
        """
    }

    public static var collectReleaseEvidenceHelpText: String {
        """
        Usage:
          design-flow collect-release-evidence --project-root <path> --run-id <id> --signoff-dashboard <path> --migration-report <path> [--pretty]

        Writes qualification/corpus-history.json, qualification/performance-envelope.json, and qualification/migration-audit.json from retained qualification reports.
        """
    }

    public static var progressRunHelpText: String {
        """
        Usage:
          design-flow progress-run --project-root <path> --run-id <id> [--since-sequence <n>] [--wait|--follow] [--timeout-milliseconds <n>] [--poll-interval-milliseconds <n>] [--pretty]

        Emits a FlowRunProgressSnapshot JSON document. With --follow, emits FlowRunProgressEvent JSONL until timeout or runFinished.
        """
    }

    public static var approveGateHelpText: String {
        """
        Usage:
          design-flow approve-gate --project-root <path> --run-id <id> --stage-id <id> --verdict <approved|rejected> --reviewer <id> [--reviewer-kind <agent|human|cli|system>] [--note <text>] [--pretty]

        Records a gate approval decision and emits a FlowGateApprovalResult JSON document.
        --reviewer-kind defaults to human; automated reviewers must pass agent, cli, or system so the ledger distinguishes human approvals from automated ones.
        """
    }

    public static var requestCancelHelpText: String {
        """
        Usage:
          design-flow request-cancel --project-root <path> --run-id <id> --requested-by <id> [--reason <text>] [--pretty]

        Records cancellation.json and a progress event. The orchestrator observes the request before the next stage starts.
        """
    }
}

private struct ProgressRunOptions {
    var request: FlowRunProgressSubscriptionRequest
    var follow: Bool
    var waitForNewEvents: Bool
    var pretty: Bool
}

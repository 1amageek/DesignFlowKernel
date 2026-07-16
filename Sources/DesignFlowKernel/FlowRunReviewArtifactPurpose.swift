import Foundation

/// An open, validated token describing how an artifact participates in flow review.
public struct FlowRunReviewArtifactPurpose: Sendable, Hashable, Codable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        do {
            try self.init(validatingRawValue: rawValue)
        } catch {
            return nil
        }
    }

    public init(validatingRawValue rawValue: String) throws {
        try FlowIdentifierValidator().validate(rawValue, kind: .reviewArtifactPurpose)
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validatingRawValue: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let actionLedger = Self(uncheckedRawValue: "action-ledger")
    public static let agentLoopSnapshot = Self(uncheckedRawValue: "agent-loop-snapshot")
    public static let approval = Self(uncheckedRawValue: "approval")
    public static let crossArtifactEvaluation = Self(uncheckedRawValue: "cross-artifact-evaluation")
    public static let designDiff = Self(uncheckedRawValue: "design-diff")
    public static let plan = Self(uncheckedRawValue: "plan")
    public static let planningActionDomain = Self(uncheckedRawValue: "planning-action-domain")
    public static let planningCandidatePlan = Self(uncheckedRawValue: "planning-candidate-plan")
    public static let planningEditedNetlist = Self(uncheckedRawValue: "planning-edited-netlist")
    public static let planningNetlistParameterEditReport = Self(uncheckedRawValue: "planning-netlist-parameter-edit-report")
    public static let planningParameterCandidateSearchTrace = Self(uncheckedRawValue: "planning-parameter-candidate-search-trace")
    public static let planningParameterCandidateSelectionTrace = Self(uncheckedRawValue: "planning-parameter-candidate-selection-trace")
    public static let planningParameterCandidates = Self(uncheckedRawValue: "planning-parameter-candidates")
    public static let planningPlanExecution = Self(uncheckedRawValue: "planning-plan-execution")
    public static let planningPlanVerification = Self(uncheckedRawValue: "planning-plan-verification")
    public static let planningProblem = Self(uncheckedRawValue: "planning-problem")
    public static let planningProblemTranslationAudit = Self(uncheckedRawValue: "planning-problem-translation-audit")
    public static let planningRejectedPlans = Self(uncheckedRawValue: "planning-rejected-plans")
    public static let planningSymbolicPlannerTrace = Self(uncheckedRawValue: "planning-symbolic-planner-trace")
    public static let postLayoutComparison = Self(uncheckedRawValue: "post-layout-comparison")
    public static let releaseEnvelope = Self(uncheckedRawValue: "release-envelope")
    public static let releaseRetentionIndex = Self(uncheckedRawValue: "release-retention-index")
    public static let retainedCIRegressionBudget = Self(uncheckedRawValue: "retained-ci-regression-budget")
    public static let retainedHistory = Self(uncheckedRawValue: "retained-history")
    public static let retainedHistoryDashboard = Self(uncheckedRawValue: "retained-history-dashboard")
    public static let retainedWorkflowReport = Self(uncheckedRawValue: "retained-workflow-report")
    public static let retentionIndex = Self(uncheckedRawValue: "retention-index")
    public static let retentionIndexReview = Self(uncheckedRawValue: "retention-index-review")
    public static let runArtifact = Self(uncheckedRawValue: "run-artifact")
    public static let runCancellationRequest = Self(uncheckedRawValue: "run-cancellation-request")
    public static let runGuardVerdict = Self(uncheckedRawValue: "run-guard-verdict")
    public static let runManifest = Self(uncheckedRawValue: "run-manifest")
    public static let runProgress = Self(uncheckedRawValue: "run-progress")
    public static let stageArtifact = Self(uncheckedRawValue: "stage-artifact")
    public static let stageArtifactLadder = Self(uncheckedRawValue: "stage-artifact-ladder")
    public static let stageAttempts = Self(uncheckedRawValue: "stage-attempts")
    public static let stageResult = Self(uncheckedRawValue: "stage-result")
    public static let stageSummary = Self(uncheckedRawValue: "stage-summary")
    public static let toolchain = Self(uncheckedRawValue: "toolchain")
    public static let toolchainProfile = Self(uncheckedRawValue: "toolchain-profile")

    private init(uncheckedRawValue rawValue: String) {
        self.rawValue = rawValue
    }
}

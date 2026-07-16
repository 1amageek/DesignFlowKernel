import Foundation

public struct FlowAgentLoopProfileValidator: Sendable {
    public init() {}

    public func validate(_ profile: FlowAgentLoopProfile) throws {
        try validateNonEmpty(profile.profileID, field: "profileID")
        try validateBudgets(profile.budgets)
        for evidence in profile.requiredEvidence {
            try validateNonEmpty(evidence.evidenceID, field: "requiredEvidence.evidenceID")
            try validateNonEmpty(evidence.artifactRole, field: "requiredEvidence.artifactRole")
            try validateNonNegative(evidence.maximumAgeSeconds, field: "requiredEvidence.maximumAgeSeconds")
        }
        for detector in profile.detectors {
            try validateNonEmpty(detector.detectorID, field: "detectors.detectorID")
            try validateNonNegative(detector.windowSize, field: "detectors.windowSize")
            if let threshold = detector.threshold, !threshold.isFinite || threshold < 0 {
                throw FlowIdentifierValidationError.invalidIdentifier(
                    kind: "agentLoopProfile",
                    value: "detectors.threshold"
                )
            }
        }
        for threshold in profile.approvalThresholds {
            try validateNonEmpty(threshold.operationKind, field: "approvalThresholds.operationKind")
        }
    }

    private func validateBudgets(_ budgets: FlowAgentLoopProfile.Budgets) throws {
        try validateNonNegative(budgets.maxActions, field: "budgets.maxActions")
        try validateNonNegative(budgets.maxElapsedSeconds, field: "budgets.maxElapsedSeconds")
        try validateNonNegative(budgets.maxToolInvocations, field: "budgets.maxToolInvocations")
        try validateNonNegative(budgets.maxChangedFiles, field: "budgets.maxChangedFiles")
        try validateNonNegative(budgets.maxDesignChanges, field: "budgets.maxDesignChanges")
    }

    private func validateNonNegative(_ value: Int?, field: String) throws {
        guard let value else {
            return
        }
        if value < 0 {
            throw FlowIdentifierValidationError.invalidIdentifier(kind: "agentLoopProfile", value: field)
        }
    }

    private func validateNonEmpty(_ value: String, field: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FlowIdentifierValidationError.invalidIdentifier(kind: "agentLoopProfile", value: field)
        }
    }
}


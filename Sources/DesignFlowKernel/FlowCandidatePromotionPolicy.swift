import Foundation

public struct FlowCandidatePromotionPolicy: Sendable, Hashable, Codable {
    public let policyID: String
    public let policyVersion: String
    public let requiredStageIDs: Set<String>
    public let approvalStageID: String
    public let requiredApprovalCount: UInt32
    public let allowWaivers: Bool
    public let requireHumanReviewer: Bool
    public let maximumArtifactByteCount: UInt64
    public let authorizationValiditySeconds: TimeInterval

    public init(
        policyID: String,
        policyVersion: String,
        requiredStageIDs: Set<String>,
        approvalStageID: String,
        requiredApprovalCount: UInt32 = 1,
        allowWaivers: Bool = false,
        requireHumanReviewer: Bool = true,
        maximumArtifactByteCount: UInt64 = 1_024 * 1_024,
        authorizationValiditySeconds: TimeInterval = 300
    ) throws {
        for (field, value) in [
            ("policyID", policyID),
            ("policyVersion", policyVersion),
            ("approvalStageID", approvalStageID),
        ] where value.isEmpty {
            throw FlowCandidatePromotionPolicyError.emptyField(field)
        }
        if requiredStageIDs.contains(where: \.isEmpty) {
            throw FlowCandidatePromotionPolicyError.emptyField("requiredStageID")
        }
        guard requiredApprovalCount > 0 else {
            throw FlowCandidatePromotionPolicyError.zeroRequiredApprovalCount
        }
        guard maximumArtifactByteCount > 0 else {
            throw FlowCandidatePromotionPolicyError.zeroArtifactBudget
        }
        guard authorizationValiditySeconds.isFinite,
              authorizationValiditySeconds > 0 else {
            throw FlowCandidatePromotionPolicyError.invalidAuthorizationValidity
        }
        self.policyID = policyID
        self.policyVersion = policyVersion
        self.requiredStageIDs = requiredStageIDs
        self.approvalStageID = approvalStageID
        self.requiredApprovalCount = requiredApprovalCount
        self.allowWaivers = allowWaivers
        self.requireHumanReviewer = requireHumanReviewer
        self.maximumArtifactByteCount = maximumArtifactByteCount
        self.authorizationValiditySeconds = authorizationValiditySeconds
    }
}

public enum FlowCandidatePromotionPolicyError: Error, Sendable, Hashable {
    case emptyField(String)
    case zeroRequiredApprovalCount
    case zeroArtifactBudget
    case invalidAuthorizationValidity
}

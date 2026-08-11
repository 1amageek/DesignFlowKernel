import CircuiteFoundation

public enum FlowCandidateEvidenceBindingValidationError: Error, Sendable, Hashable {
    case bindingDigestMismatch(expected: ContentDigest, actual: ContentDigest)
    case bindingDigestComputationFailed(String)
    case crossDatabaseBaseRevision(
        base: DesignDatabaseID,
        candidate: DesignDatabaseID
    )
    case duplicateStageID(String)
    case candidateRevisionMismatch(
        stageID: String,
        expected: DesignRevisionReference,
        actual: DesignRevisionReference
    )
    case semanticGraphDigestMismatch(
        stageID: String,
        expected: ContentDigest,
        actual: ContentDigest
    )
    case missingRequiredStage(String)
    case requiredStageDidNotSucceed(stageID: String, status: FlowStageStatus)
}

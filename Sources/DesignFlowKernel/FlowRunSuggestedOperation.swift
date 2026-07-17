import CircuiteFoundation
import Foundation

public enum FlowRunSuggestedOperation: Sendable, Hashable, Codable {
    case summarizeRunLoop
    case inspectRun
    case reviewRun
    case evaluateRunGuard
    case validatePlanningProblem
    case auditProblemTranslation
    case generateCandidatePlan(rejectedPlansArtifactID: ArtifactID?)
    case executeCandidatePlan
    case verifyCandidatePlan(scope: FlowRunVerificationScope)
    case generateParameterCandidates
    case synthesizeParameterCandidatePlan
    case runNumericRepairLoop
    case buildStageArtifactLadder
    case validateDecisionPacket
    case buildReleaseEnvelope
}

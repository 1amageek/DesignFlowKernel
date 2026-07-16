import Foundation

/// Provides a domain-specific integrity gate for an approval before the flow
/// kernel resumes past a generic approval gate.
public protocol FlowStageApprovalValidating: Sendable {
    func validateApproval(
        _ approval: FlowApprovalRecord,
        reviewedResult: FlowStageResult,
        context: FlowExecutionContext
    ) throws -> [FlowDiagnostic]
}

import Foundation
import XcircuitePackage

/// Provides a domain-specific integrity gate for an approval before the flow
/// kernel resumes past a generic approval gate.
public protocol FlowStageApprovalValidating: Sendable {
    func validateApproval(
        _ approval: XcircuiteApprovalRecord,
        reviewedResult: FlowStageResult,
        context: FlowExecutionContext
    ) throws -> [FlowDiagnostic]
}

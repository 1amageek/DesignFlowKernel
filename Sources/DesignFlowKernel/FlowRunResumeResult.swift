import Foundation

public struct FlowRunResumeResult: Sendable, Hashable, Codable {
    public var result: FlowRunResult
    public var summary: FlowRunLedgerSummary

    public init(result: FlowRunResult, summary: FlowRunLedgerSummary) {
        self.result = result
        self.summary = summary
    }
}

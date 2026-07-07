import Foundation

public protocol FlowRunLedgerSummarizing: Sendable {
    func summarize(_ ledger: FlowRunLedger) -> FlowRunLedgerSummary
}

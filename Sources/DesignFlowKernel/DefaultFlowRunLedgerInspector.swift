import Foundation

public struct DefaultFlowRunLedgerInspector: FlowRunLedgerInspecting {
    private let loader: FlowRunLedgerLoading
    private let summarizer: FlowRunLedgerSummarizing

    public init(
        loader: FlowRunLedgerLoading = FlowRunLedgerLoader(),
        summarizer: FlowRunLedgerSummarizing = DefaultFlowRunLedgerSummarizer()
    ) {
        self.loader = loader
        self.summarizer = summarizer
    }

    public func inspectRun(runID: String, projectRoot: URL) throws -> FlowRunLedgerSummary {
        let ledger = try loader.loadRunLedger(runID: runID, projectRoot: projectRoot)
        return summarizer.summarize(ledger)
    }
}

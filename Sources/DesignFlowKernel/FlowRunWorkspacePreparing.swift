public protocol FlowRunWorkspacePreparing: Sendable {
    func prepareRun(
        runID: String,
        requireNew: Bool
    ) async throws
}

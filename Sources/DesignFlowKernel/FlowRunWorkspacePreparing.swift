import Foundation

public protocol FlowRunWorkspacePreparing: Sendable {
    func prepareRunWorkspace(
        runID: String,
        requireNew: Bool
    ) async throws -> URL

    func runWorkspaceURL(runID: String) async throws -> URL
}

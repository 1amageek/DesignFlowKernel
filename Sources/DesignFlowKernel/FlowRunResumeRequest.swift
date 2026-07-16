import Foundation

public struct FlowRunResumeRequest: Sendable, Hashable, Codable {
    public var workspaceID: FlowWorkspaceID
    public var runID: String

    public init(workspaceID: FlowWorkspaceID, runID: String) {
        self.workspaceID = workspaceID
        self.runID = runID
    }
}

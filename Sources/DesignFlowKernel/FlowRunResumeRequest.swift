import Foundation

public struct FlowRunResumeRequest: Sendable, Hashable, Codable {
    public var projectRoot: URL
    public var runID: String

    public init(projectRoot: URL, runID: String) {
        self.projectRoot = projectRoot
        self.runID = runID
    }
}

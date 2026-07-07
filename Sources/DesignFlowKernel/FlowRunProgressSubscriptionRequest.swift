import Foundation

public struct FlowRunProgressSubscriptionRequest: Sendable, Hashable {
    public var projectRoot: URL
    public var runID: String
    public var afterSequence: Int
    public var waitForNewEvents: Bool
    public var timeoutMilliseconds: Int
    public var pollIntervalMilliseconds: Int
    public var stopWhenRunFinished: Bool

    public init(
        projectRoot: URL,
        runID: String,
        afterSequence: Int = 0,
        waitForNewEvents: Bool = false,
        timeoutMilliseconds: Int = 0,
        pollIntervalMilliseconds: Int = 250,
        stopWhenRunFinished: Bool = true
    ) {
        self.projectRoot = projectRoot
        self.runID = runID
        self.afterSequence = afterSequence
        self.waitForNewEvents = waitForNewEvents
        self.timeoutMilliseconds = timeoutMilliseconds
        self.pollIntervalMilliseconds = pollIntervalMilliseconds
        self.stopWhenRunFinished = stopWhenRunFinished
    }
}

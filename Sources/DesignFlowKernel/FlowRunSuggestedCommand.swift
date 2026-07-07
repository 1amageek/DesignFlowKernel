import Foundation

public struct FlowRunSuggestedCommand: Sendable, Hashable, Codable {
    public var commandID: String
    public var readiness: FlowRunSuggestedCommandReadiness
    public var executable: String
    public var arguments: [String]
    public var reason: String

    public init(
        commandID: String,
        readiness: FlowRunSuggestedCommandReadiness,
        executable: String,
        arguments: [String],
        reason: String
    ) {
        self.commandID = commandID
        self.readiness = readiness
        self.executable = executable
        self.arguments = arguments
        self.reason = reason
    }
}

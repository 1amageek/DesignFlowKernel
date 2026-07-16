import Foundation

public struct FlowRunDescriptor: Sendable, Hashable {
    public var actor: FlowRunActor
    public var intent: String?
    public var parentRunID: String?
    public var createdAt: Date

    public init(
        actor: FlowRunActor = FlowRunActor(
            kind: .system,
            identifier: "xcircuite-workspace"
        ),
        intent: String? = nil,
        parentRunID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.actor = actor
        self.intent = intent
        self.parentRunID = parentRunID
        self.createdAt = createdAt
    }
}

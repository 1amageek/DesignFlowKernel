import Foundation

public struct XcircuiteRunDescriptor: Sendable, Hashable {
    public var actor: XcircuiteRunActionActor
    public var intent: String?
    public var parentRunID: String?
    public var createdAt: Date

    public init(
        actor: XcircuiteRunActionActor = XcircuiteRunActionActor(
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

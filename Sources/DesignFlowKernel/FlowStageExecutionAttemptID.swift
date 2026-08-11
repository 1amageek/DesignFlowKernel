import Foundation

public struct FlowStageExecutionAttemptID: Sendable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) throws {
        try FlowIdentifierValidator().validate(rawValue, kind: .stageExecutionAttemptID)
        self.rawValue = rawValue
    }

    public static func generated() -> FlowStageExecutionAttemptID {
        FlowStageExecutionAttemptID(
            validatedRawValue: UUID().uuidString.lowercased()
        )
    }

    private init(validatedRawValue: String) {
        self.rawValue = validatedRawValue
    }
}

import Foundation

public struct FlowStageRetryPolicy: Sendable, Hashable, Codable {
    public var maxAttempts: Int
    public var retryableDiagnosticCodes: [String]

    public init(
        maxAttempts: Int = 1,
        retryableDiagnosticCodes: [String] = []
    ) {
        self.maxAttempts = maxAttempts
        self.retryableDiagnosticCodes = retryableDiagnosticCodes
    }

    public static var disabled: FlowStageRetryPolicy {
        FlowStageRetryPolicy()
    }

    public var isEnabled: Bool {
        maxAttempts > 1 && !retryableDiagnosticCodes.isEmpty
    }
}

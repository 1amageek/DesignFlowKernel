import Foundation

public struct DesignFlowCLIErrorReport: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    public let status: String
    public let exitCode: Int
    public let diagnostic: DesignFlowCLIErrorDiagnostic

    public init(
        schemaVersion: Int = 1,
        status: String = "failed",
        exitCode: Int,
        diagnostic: DesignFlowCLIErrorDiagnostic
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.exitCode = exitCode
        self.diagnostic = diagnostic
    }
}

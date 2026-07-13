import Foundation

public protocol FlowRunReleaseRetentionIndexValidating: Sendable {
    func validate(
        index: FlowRunReleaseRetentionIndex,
        runID: String,
        projectRoot: URL,
        currentDate: Date,
        maximumAgeSeconds: TimeInterval?
    ) throws -> FlowRunReleaseRetentionValidationResult
}

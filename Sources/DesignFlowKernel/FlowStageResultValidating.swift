public protocol FlowStageResultValidating: Sendable {
    func validate(
        _ result: FlowStageResult,
        expectedStageID: String
    ) throws
}

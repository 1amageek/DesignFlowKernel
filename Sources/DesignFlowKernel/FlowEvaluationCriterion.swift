import Foundation

public struct FlowEvaluationCriterion: Sendable, Hashable, Codable {
    public var criterionID: String
    public var channelID: String
    public var comparator: FlowEvaluationComparator
    public var target: FlowMetricValue?
    public var tolerance: Double?
    public var weight: Double
    public var required: Bool
    public var context: FlowEvaluationContext?

    public init(
        criterionID: String,
        channelID: String,
        comparator: FlowEvaluationComparator,
        target: FlowMetricValue? = nil,
        tolerance: Double? = nil,
        weight: Double = 1,
        required: Bool = true,
        context: FlowEvaluationContext? = nil
    ) {
        self.criterionID = criterionID
        self.channelID = channelID
        self.comparator = comparator
        self.target = target
        self.tolerance = tolerance
        self.weight = weight
        self.required = required
        self.context = context
    }
}

import Foundation

public struct XcircuiteEvaluationCriterion: Sendable, Hashable, Codable {
    public var criterionID: String
    public var channelID: String
    public var comparator: XcircuiteEvaluationComparator
    public var target: XcircuiteJSONValue?
    public var tolerance: Double?
    public var weight: Double
    public var required: Bool
    public var metadata: [String: XcircuiteJSONValue]

    public init(
        criterionID: String,
        channelID: String,
        comparator: XcircuiteEvaluationComparator,
        target: XcircuiteJSONValue? = nil,
        tolerance: Double? = nil,
        weight: Double = 1,
        required: Bool = true,
        metadata: [String: XcircuiteJSONValue] = [:]
    ) {
        self.criterionID = criterionID
        self.channelID = channelID
        self.comparator = comparator
        self.target = target
        self.tolerance = tolerance
        self.weight = weight
        self.required = required
        self.metadata = metadata
    }
}

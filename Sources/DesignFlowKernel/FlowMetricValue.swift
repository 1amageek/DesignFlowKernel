import Foundation

public enum FlowMetricValue: Sendable, Hashable, Codable {
    case boolean(Bool)
    case scalar(Double)
    case quantity(value: Double, unit: String)
    case text(String)
    case vector([Double])
}

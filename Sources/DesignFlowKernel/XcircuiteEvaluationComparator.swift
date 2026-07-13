import Foundation

public enum XcircuiteEvaluationComparator: String, Sendable, Hashable, Codable {
    case equal
    case notEqual
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
    case range
    case custom
}

import Foundation

public enum FlowGateStatus: String, Sendable, Hashable, Codable {
    case passed
    case failed
    case waived
    case incomplete
}

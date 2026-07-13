import Foundation

public enum XcircuiteObservationChannelStatus: String, Sendable, Hashable, Codable {
    case observed
    case missing
    case uncalibrated
    case derived
    case failed
}

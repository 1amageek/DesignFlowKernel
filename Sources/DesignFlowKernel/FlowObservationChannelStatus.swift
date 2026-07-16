import Foundation

public enum FlowObservationChannelStatus: String, Sendable, Hashable, Codable {
    case observed
    case missing
    case uncalibrated
    case derived
    case failed
}

import Foundation

public struct XcircuiteEvidenceConfidence: Sendable, Hashable, Codable {
    public var value: Double?
    public var posteriorVariance: Double?
    public var calibrationCoefficient: Double?
    public var calibrated: Bool

    public init(
        value: Double? = nil,
        posteriorVariance: Double? = nil,
        calibrationCoefficient: Double? = nil,
        calibrated: Bool = false
    ) {
        self.value = value
        self.posteriorVariance = posteriorVariance
        self.calibrationCoefficient = calibrationCoefficient
        self.calibrated = calibrated
    }
}

import Foundation

public enum FlowArtifactBindingError: Error, LocalizedError, Sendable, Equatable {
    case invalidLogicalID(String)
    case availabilityIdentityMismatch
    case localAvailabilityRequired(logicalID: String)

    public var errorDescription: String? {
        switch self {
        case .invalidLogicalID(let logicalID):
            "Invalid flow artifact logical ID: \(logicalID)."
        case .availabilityIdentityMismatch:
            "Flow artifact availability does not identify the bound content."
        case .localAvailabilityRequired(let logicalID):
            "Flow artifact '\(logicalID)' requires local availability for this operation."
        }
    }
}

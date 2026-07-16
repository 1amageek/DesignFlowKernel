import Foundation

public enum DesignDiffDomain: String, Sendable, Hashable, Codable {
    case project
    case schematic
    case layout
    case netlist
    case simulation
    case verification
    case pex
    case review
    case other
}

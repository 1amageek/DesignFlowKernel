import Foundation

@available(*, deprecated, message: "Use CircuiteFoundation.ArtifactKind.")
public enum XcircuiteFileKind: String, Sendable, Hashable, Codable {
    case request
    case rtl
    case netlist
    case layout
    case technology
    case constraint
    case powerIntent
    case timingLibrary
    case parasitic
    case waveform
    case testPattern
    case report
    case log
    case ruleDeck
    case model
    case measurement
    case designDiff
    case release
    case other
}

import Foundation

/// A read-only projection resolved from a project run locator and its canonical manifest.
public struct XcircuiteRunSnapshot: Sendable, Hashable {
    public let reference: XcircuiteRunReference
    public let manifest: XcircuiteRunManifest

    public init(reference: XcircuiteRunReference, manifest: XcircuiteRunManifest) {
        self.reference = reference
        self.manifest = manifest
    }

    public var runID: String { manifest.runID }
    public var status: XcircuiteRunStatus { manifest.status }
}

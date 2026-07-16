import Foundation

/// A read-only projection resolved from a project run locator and its canonical manifest.
public struct FlowRunSnapshot: Sendable, Hashable {
    public let reference: FlowRunReference
    public let manifest: FlowRunManifest

    public init(reference: FlowRunReference, manifest: FlowRunManifest) {
        self.reference = reference
        self.manifest = manifest
    }

    public var runID: String { manifest.runID }
    public var status: FlowRunStatus { manifest.status }
}

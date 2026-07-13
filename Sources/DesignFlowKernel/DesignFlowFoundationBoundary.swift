import Foundation
@_exported import CircuiteFoundation

/// Errors raised when a flow result cannot be represented by the shared
/// Foundation evidence contract without losing artifact integrity.
public enum DesignFlowFoundationBoundaryError: Error, Sendable, Equatable, LocalizedError {
    case missingDigest(String)
    case missingByteCount(String)
    case invalidByteCount(String)
    case invalidArtifactLocation(String)
    case invalidArtifactIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .missingDigest(let path):
            "Design-flow artifact has no SHA-256 digest: \(path)"
        case .missingByteCount(let path):
            "Design-flow artifact has no byte count: \(path)"
        case .invalidByteCount(let path):
            "Design-flow artifact has an invalid byte count: \(path)"
        case .invalidArtifactLocation(let path):
            "Design-flow artifact has an invalid location: \(path)"
        case .invalidArtifactIdentifier(let identifier):
            "Design-flow artifact has an invalid artifact identifier: \(identifier)"
        }
    }
}

/// Shared evidence view for flow orchestration.
///
/// DesignFlowKernel owns stage ordering, retry, approval, and resume state.
/// Domain engines own their own result models. This value is the explicit
/// boundary that lets callers consume a run through CircuiteFoundation while
/// retaining the domain-specific `FlowRunResult` as the source of truth.
public struct DesignFlowFoundationEvidence: Sendable, Hashable, Codable, ArtifactProducing,
    EvidenceProviding, DiagnosticReporting
{
    public let evidence: EvidenceManifest
    public let diagnostics: [DesignDiagnostic]

    public var artifacts: [ArtifactReference] { evidence.artifacts }

    public init(
        result: FlowRunResult,
        provenance: ExecutionProvenance
    ) throws {
        let references = try result.stages
            .flatMap(\.artifacts)
            .map { try Self.makeArtifactReference($0) }
        self.evidence = EvidenceManifest(
            provenance: provenance,
            artifacts: references
        )
        self.diagnostics = try result.stages
            .flatMap(\.diagnostics)
            .map(Self.makeDiagnostic)
    }

    private static func makeArtifactReference(
        _ reference: ArtifactReference
    ) throws -> ArtifactReference {
        guard !reference.digest.hexadecimalValue.isEmpty else {
            throw DesignFlowFoundationBoundaryError.missingDigest(reference.path)
        }
        guard reference.byteCount <= UInt64(Int64.max) else {
            throw DesignFlowFoundationBoundaryError.invalidByteCount(reference.path)
        }
        let kind = try ArtifactKind(rawValue: "flow.\(reference.kind.rawValue)")
        return ArtifactReference(
            id: reference.id,
            locator: ArtifactLocator(
                location: reference.locator.location,
                role: reference.locator.role,
                kind: kind,
                format: reference.locator.format
            ),
            digest: reference.digest,
            byteCount: reference.byteCount,
            producer: reference.producer
        )
    }

    private static func makeDiagnostic(_ diagnostic: FlowDiagnostic) throws -> DesignDiagnostic {
        let code = try DiagnosticCode(rawValue: "flow.\(diagnostic.code)")
        let severity: DiagnosticSeverity
        switch diagnostic.severity {
        case .info:
            severity = .information
        case .warning:
            severity = .warning
        case .error:
            severity = .error
        }
        return DesignDiagnostic(
            code: code,
            severity: severity,
            summary: diagnostic.message
        )
    }
}

extension FlowOperationRequest {
    /// Returns a Foundation hierarchy identity for a flow whose first stage
    /// targets a design object. Stages remain flow-owned; this helper is only
    /// for callers that provide a canonical object identifier in the intent.
    public func designObjectReference(identifier: String) throws -> DesignObjectReference {
        try DesignObjectReference(kind: .cell, identifier: identifier)
    }
}

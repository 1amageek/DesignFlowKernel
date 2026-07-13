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
            .map(Self.makeArtifactReference)
        self.evidence = EvidenceManifest(
            provenance: provenance,
            artifacts: references
        )
        self.diagnostics = try result.stages
            .flatMap(\.diagnostics)
            .map(Self.makeDiagnostic)
    }

    private static func makeArtifactReference(
        _ reference: XcircuiteFileReference
    ) throws -> ArtifactReference {
        guard let sha256 = reference.sha256, !sha256.isEmpty else {
            throw DesignFlowFoundationBoundaryError.missingDigest(reference.path)
        }
        guard let byteCount = reference.byteCount else {
            throw DesignFlowFoundationBoundaryError.missingByteCount(reference.path)
        }
        guard byteCount >= 0 else {
            throw DesignFlowFoundationBoundaryError.invalidByteCount(reference.path)
        }

        let location: ArtifactLocation
        do {
            if reference.path.hasPrefix("/") {
                location = try ArtifactLocation(fileURL: URL(fileURLWithPath: reference.path))
            } else {
                location = try ArtifactLocation(workspaceRelativePath: reference.path)
            }
        } catch {
            throw DesignFlowFoundationBoundaryError.invalidArtifactLocation(reference.path)
        }

        let artifactID: ArtifactID?
        if let rawArtifactID = reference.artifactID {
            do {
                artifactID = try ArtifactID(rawValue: rawArtifactID)
            } catch {
                throw DesignFlowFoundationBoundaryError.invalidArtifactIdentifier(rawArtifactID)
            }
        } else {
            artifactID = nil
        }
        let digest = try ContentDigest(algorithm: .sha256, hexadecimalValue: sha256)
        let kind = try ArtifactKind(rawValue: "flow.\(reference.kind.rawValue)")
        let format = try makeArtifactFormat(reference.format)

        return ArtifactReference(
            id: artifactID,
            locator: ArtifactLocator(location: location, kind: kind, format: format),
            digest: digest,
            byteCount: UInt64(byteCount)
        )
    }

    private static func makeArtifactFormat(
        _ format: XcircuiteFileFormat
    ) throws -> ArtifactFormat {
        switch format {
        case .spice:
            return .spice
        case .systemVerilog:
            return .systemVerilog
        case .verilog:
            return .verilog
        case .oasis:
            return .oasis
        case .gdsii:
            return .gdsii
        case .lef:
            return .lef
        case .def:
            return .def
        case .spef:
            return .spef
        case .dspf:
            return .dspf
        case .liberty:
            return .liberty
        case .sdc:
            return try ArtifactFormat(rawValue: "sdc")
        case .sdf:
            return .sdf
        case .upf:
            return try ArtifactFormat(rawValue: "upf")
        case .cpf:
            return try ArtifactFormat(rawValue: "cpf")
        case .vcd:
            return .vcd
        case .fst:
            return try ArtifactFormat(rawValue: "fst")
        case .stil:
            return try ArtifactFormat(rawValue: "stil")
        case .wgl:
            return try ArtifactFormat(rawValue: "wgl")
        case .json:
            return .json
        case .raw:
            return try ArtifactFormat(rawValue: "raw")
        case .csv:
            return try ArtifactFormat(rawValue: "csv")
        case .text:
            return try ArtifactFormat(rawValue: "text")
        case .unknown:
            return try ArtifactFormat(rawValue: "unknown")
        }
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

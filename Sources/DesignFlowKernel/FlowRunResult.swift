import CircuiteFoundation
import Foundation

public struct FlowRunResult: Sendable, Hashable, Codable, ArtifactProducing,
    DiagnosticReporting, EvidenceProviding
{
    public let runID: String
    public let status: FlowRunStatus
    public let stages: [FlowStageResult]
    public let evidence: EvidenceManifest
    public let diagnostics: [DesignDiagnostic]

    public var artifacts: [ArtifactReference] { evidence.artifacts }

    public init(
        runID: String,
        status: FlowRunStatus,
        stages: [FlowStageResult],
        provenance: ExecutionProvenance
    ) throws {
        self.runID = runID
        self.status = status
        self.stages = stages
        self.evidence = EvidenceManifest(
            provenance: provenance,
            artifacts: stages.flatMap(\.artifacts)
        )
        self.diagnostics = try stages
            .flatMap(\.diagnostics)
            .map(Self.makeDiagnostic)
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case status
        case stages
        case evidence
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let runID = try container.decode(String.self, forKey: .runID)
        let status = try container.decode(FlowRunStatus.self, forKey: .status)
        let stages = try container.decode([FlowStageResult].self, forKey: .stages)
        let evidence = try container.decode(EvidenceManifest.self, forKey: .evidence)
        let diagnostics = try container.decode([DesignDiagnostic].self, forKey: .diagnostics)
        try Self.validate(stages: stages, evidence: evidence, diagnostics: diagnostics)
        self.runID = runID
        self.status = status
        self.stages = stages
        self.evidence = evidence
        self.diagnostics = diagnostics
    }

    public func encode(to encoder: Encoder) throws {
        try Self.validate(stages: stages, evidence: evidence, diagnostics: diagnostics)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runID, forKey: .runID)
        try container.encode(status, forKey: .status)
        try container.encode(stages, forKey: .stages)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(diagnostics, forKey: .diagnostics)
    }

    private static func validate(
        stages: [FlowStageResult],
        evidence: EvidenceManifest,
        diagnostics: [DesignDiagnostic]
    ) throws {
        guard evidence.artifacts == stages.flatMap(\.artifacts) else {
            throw FlowRunResultValidationError.artifactEvidenceMismatch
        }
        let expectedDiagnostics = try stages
            .flatMap(\.diagnostics)
            .map(makeDiagnostic)
        guard diagnostics == expectedDiagnostics else {
            throw FlowRunResultValidationError.diagnosticEvidenceMismatch
        }
    }

    private static func makeDiagnostic(_ diagnostic: FlowDiagnostic) throws -> DesignDiagnostic {
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
            code: try DiagnosticCode(rawValue: diagnostic.code),
            severity: severity,
            summary: diagnostic.message
        )
    }
}

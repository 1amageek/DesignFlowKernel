import CircuiteFoundation
import Foundation
import Testing
@testable import DesignFlowKernel

@Suite("FlowArtifactEnvelopeValidator")
struct FlowArtifactEnvelopeValidatorTests {
    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func rejectsNonFiniteConfidence(_ value: Double) throws {
        var envelope = try validEnvelope()
        envelope.evaluationResult?.confidence = FlowEvidenceConfidence(value: value)

        #expect(throws: FlowArtifactEnvelopeValidationError.self) {
            try FlowArtifactEnvelopeValidator().validate(envelope)
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func rejectsNonFinitePosteriorVariance(_ value: Double) throws {
        var envelope = try validEnvelope()
        envelope.observationSet?.confidence = FlowEvidenceConfidence(
            posteriorVariance: value
        )

        #expect(throws: FlowArtifactEnvelopeValidationError.self) {
            try FlowArtifactEnvelopeValidator().validate(envelope)
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func rejectsNonFiniteLikelihoodResidualToleranceAndMetrics(_ value: Double) throws {
        var likelihood = try validEnvelope()
        likelihood.evaluationResult?.likelihood = value
        #expect(throws: FlowArtifactEnvelopeValidationError.self) {
            try FlowArtifactEnvelopeValidator().validate(likelihood)
        }

        var residual = try validEnvelope()
        residual.evaluationResult?.residual = value
        #expect(throws: FlowArtifactEnvelopeValidationError.self) {
            try FlowArtifactEnvelopeValidator().validate(residual)
        }

        var tolerance = try validEnvelope()
        tolerance.evaluationSpec?.criteria[0].tolerance = value
        #expect(throws: FlowArtifactEnvelopeValidationError.self) {
            try FlowArtifactEnvelopeValidator().validate(tolerance)
        }

        var metric = try validEnvelope()
        metric.observationSet?.channels[0].value = .vector([1, value])
        #expect(throws: FlowArtifactEnvelopeValidationError.self) {
            try FlowArtifactEnvelopeValidator().validate(metric)
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func rejectsNonFiniteContextGeometry(_ value: Double) throws {
        var envelope = try validEnvelope()
        envelope.evaluationResult?.channelResults[0].context = FlowEvaluationContext(
            region: .init(x: value, y: 0, width: 1, height: 1)
        )

        #expect(throws: FlowArtifactEnvelopeValidationError.self) {
            try FlowArtifactEnvelopeValidator().validate(envelope)
        }
    }

    @Test
    func acceptsFiniteEvidence() throws {
        try FlowArtifactEnvelopeValidator().validate(validEnvelope())
    }

    private func validEnvelope() throws -> FlowArtifactEnvelope {
        let reference = ArtifactReference(
            id: try ArtifactID(rawValue: "evidence-1"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: ".xcircuite/runs/run-1/evidence.json"),
                role: .output,
                kind: .evidence,
                format: .json
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "0", count: 64)
            ),
            byteCount: 1
        )
        return FlowArtifactEnvelope(
            artifactID: "evidence-1",
            role: "qualification-evidence",
            reference: reference,
            evaluationSpec: FlowEvaluationSpec(
                specID: "spec-1",
                objective: "Validate finite evidence",
                criteria: [
                    FlowEvaluationCriterion(
                        criterionID: "criterion-1",
                        channelID: "channel-1",
                        comparator: .lessThanOrEqual,
                        target: .scalar(1),
                        tolerance: 0.01
                    )
                ]
            ),
            observationSet: FlowObservationSet(
                observationSetID: "observations-1",
                channels: [
                    FlowObservationChannel(
                        channelID: "channel-1",
                        status: .observed,
                        value: .scalar(0.5)
                    )
                ]
            ),
            evaluationResult: FlowEvaluationResult(
                evaluationID: "evaluation-1",
                specID: "spec-1",
                status: .accepted,
                likelihood: 1,
                residual: 0,
                channelResults: [
                    FlowEvaluationChannelResult(
                        criterionID: "criterion-1",
                        channelID: "channel-1",
                        status: .accepted,
                        observedValue: .scalar(0.5),
                        residual: 0,
                        likelihood: 1
                    )
                ],
                summary: "Passed"
            )
        )
    }
}

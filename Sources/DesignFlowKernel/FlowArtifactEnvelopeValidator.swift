import Foundation

public struct FlowArtifactEnvelopeValidator: Sendable {
    private let identifierValidator: FlowIdentifierValidator

    public init(identifierValidator: FlowIdentifierValidator = FlowIdentifierValidator()) {
        self.identifierValidator = identifierValidator
    }

    public func validate(_ envelope: FlowArtifactEnvelope) throws {
        guard envelope.schemaVersion == 1 else {
            throw FlowArtifactEnvelopeValidationError.invalidSchemaVersion(envelope.schemaVersion)
        }
        try validateIdentifier(envelope.artifactID, field: "artifactID", kind: .artifactID)
        try validateNonEmpty(envelope.role, field: "role")
        try validateNonEmpty(envelope.reference.path, field: "reference.path")
        if envelope.reference.artifactID != envelope.artifactID {
            throw FlowArtifactEnvelopeValidationError.artifactIDMismatch(
                envelopeArtifactID: envelope.artifactID,
                referenceArtifactID: envelope.reference.artifactID
            )
        }
        try validateProducer(envelope.producer)
        try validateDependencies(envelope.inputs, field: "inputs")
        try validateDependencies(envelope.dependencies, field: "dependencies")
        try validateEvaluationSpec(envelope.evaluationSpec)
        try validateObservationSet(envelope.observationSet)
        try validateEvaluationResult(envelope.evaluationResult)
        try validateDelegationCertificate(envelope.delegationCertificate)
    }

    private func validateProducer(_ producer: FlowArtifactProducer?) throws {
        guard let producer else {
            return
        }
        try validateNonEmpty(producer.producerID, field: "producer.producerID")
    }

    private func validateDependencies(
        _ dependencies: [FlowArtifactDependency],
        field: String
    ) throws {
        for dependency in dependencies {
            if let artifactID = dependency.artifactID {
                try validateIdentifier(artifactID, field: "\(field).artifactID", kind: .artifactID)
            }
            try validateNonEmpty(dependency.path, field: "\(field).path")
            try validateNonEmpty(dependency.role, field: "\(field).role")
        }
    }

    private func validateEvaluationSpec(_ spec: FlowEvaluationSpec?) throws {
        guard let spec else {
            return
        }
        guard spec.schemaVersion == 1 else {
            throw FlowArtifactEnvelopeValidationError.invalidSchemaVersion(spec.schemaVersion)
        }
        try validateNonEmpty(spec.specID, field: "evaluationSpec.specID")
        try validateNonEmpty(spec.objective, field: "evaluationSpec.objective")
        try validateConfidence(spec.confidence, field: "evaluationSpec.confidence")
        for criterion in spec.criteria {
            try validateNonEmpty(criterion.criterionID, field: "evaluationSpec.criteria.criterionID")
            try validateNonEmpty(criterion.channelID, field: "evaluationSpec.criteria.channelID")
            try validateMetricValue(
                criterion.target,
                field: "evaluationSpec.criteria.target"
            )
            try validateFinite(criterion.tolerance, field: "evaluationSpec.criteria.tolerance")
            try validateFinite(criterion.weight, field: "evaluationSpec.criteria.weight")
            try validateContext(
                criterion.context,
                field: "evaluationSpec.criteria.context"
            )
        }
    }

    private func validateObservationSet(_ observationSet: FlowObservationSet?) throws {
        guard let observationSet else {
            return
        }
        try validateNonEmpty(observationSet.observationSetID, field: "observationSet.observationSetID")
        try validateConfidence(observationSet.confidence, field: "observationSet.confidence")
        for channel in observationSet.channels {
            try validateNonEmpty(channel.channelID, field: "observationSet.channels.channelID")
            try validateConfidence(channel.confidence, field: "observationSet.channels.confidence")
            try validateMetricValue(channel.value, field: "observationSet.channels.value")
            try validateContext(channel.context, field: "observationSet.channels.context")
        }
    }

    private func validateEvaluationResult(_ result: FlowEvaluationResult?) throws {
        guard let result else {
            return
        }
        guard result.schemaVersion == 1 else {
            throw FlowArtifactEnvelopeValidationError.invalidSchemaVersion(result.schemaVersion)
        }
        try validateNonEmpty(result.evaluationID, field: "evaluationResult.evaluationID")
        try validateNonEmpty(result.specID, field: "evaluationResult.specID")
        try validateUnitInterval(result.likelihood, field: "evaluationResult.likelihood")
        try validateFinite(result.residual, field: "evaluationResult.residual")
        try validateConfidence(result.confidence, field: "evaluationResult.confidence")
        for channelResult in result.channelResults {
            try validateNonEmpty(
                channelResult.channelID,
                field: "evaluationResult.channelResults.channelID"
            )
            try validateUnitInterval(
                channelResult.likelihood,
                field: "evaluationResult.channelResults.likelihood"
            )
            try validateMetricValue(
                channelResult.observedValue,
                field: "evaluationResult.channelResults.observedValue"
            )
            try validateFinite(
                channelResult.residual,
                field: "evaluationResult.channelResults.residual"
            )
            try validateContext(
                channelResult.context,
                field: "evaluationResult.channelResults.context"
            )
            try validateConfidence(
                channelResult.confidence,
                field: "evaluationResult.channelResults.confidence"
            )
        }
        try validateFeedbackSignals(result.feedbackSignals, field: "evaluationResult.feedbackSignals")
    }

    private func validateFeedbackSignals(
        _ signals: [FlowFeedbackSignal],
        field: String
    ) throws {
        for signal in signals {
            try validateNonEmpty(signal.signalID, field: "\(field).signalID")
            try validateNonEmpty(signal.summary, field: "\(field).summary")
            try validateFinite(signal.residual, field: "\(field).residual")
            try validateConfidence(signal.confidence, field: "\(field).confidence")
        }
    }

    private func validateDelegationCertificate(
        _ certificate: FlowDelegationCertificate?
    ) throws {
        guard let certificate else {
            return
        }
        try validateNonEmpty(certificate.certificateID, field: "delegationCertificate.certificateID")
        try validateNonEmpty(certificate.issuedBy, field: "delegationCertificate.issuedBy")
        try validateNonEmpty(certificate.issuedTo, field: "delegationCertificate.issuedTo")
        try validateNonEmpty(certificate.scope, field: "delegationCertificate.scope")
    }

    private func validateConfidence(
        _ confidence: FlowEvidenceConfidence?,
        field: String
    ) throws {
        guard let confidence else {
            return
        }
        try validateUnitInterval(confidence.value, field: "\(field).value")
        try validateUnitInterval(
            confidence.calibrationCoefficient,
            field: "\(field).calibrationCoefficient"
        )
        try validateFinite(
            confidence.posteriorVariance,
            field: "\(field).posteriorVariance"
        )
        if let posteriorVariance = confidence.posteriorVariance, posteriorVariance < 0 {
            throw FlowArtifactEnvelopeValidationError.invalidPosteriorVariance(
                field: "\(field).posteriorVariance",
                value: posteriorVariance
            )
        }
    }

    private func validateUnitInterval(_ value: Double?, field: String) throws {
        guard let value else {
            return
        }
        try validateFinite(value, field: field)
        guard value >= 0, value <= 1 else {
            throw FlowArtifactEnvelopeValidationError.invalidConfidence(
                field: field,
                value: value
            )
        }
    }

    private func validateMetricValue(_ value: FlowMetricValue?, field: String) throws {
        guard let value else {
            return
        }
        switch value {
        case .boolean, .text:
            return
        case .scalar(let scalar):
            try validateFinite(scalar, field: field)
        case .quantity(let value, _):
            try validateFinite(value, field: field)
        case .vector(let values):
            for (index, value) in values.enumerated() {
                try validateFinite(value, field: "\(field)[\(index)]")
            }
        }
    }

    private func validateContext(_ context: FlowEvaluationContext?, field: String) throws {
        guard let context else {
            return
        }
        let values: [(String, Double?)] = [
            ("minimumValue", context.minimumValue),
            ("maximumValue", context.maximumValue),
            ("relativeSpread", context.relativeSpread),
            ("requiredValue", context.requiredValue),
            ("maximumMeasuredValue", context.maximumMeasuredValue),
            ("region.x", context.region?.x),
            ("region.y", context.region?.y),
            ("region.width", context.region?.width),
            ("region.height", context.region?.height),
        ]
        for (name, value) in values {
            try validateFinite(value, field: "\(field).\(name)")
        }
    }

    private func validateFinite(_ value: Double?, field: String) throws {
        guard let value else {
            return
        }
        guard value.isFinite else {
            throw FlowArtifactEnvelopeValidationError.nonFiniteNumericValue(
                field: field,
                value: value
            )
        }
    }

    private func validateNonEmpty(_ value: String, field: String) throws {
        guard !value.isEmpty else {
            throw FlowArtifactEnvelopeValidationError.emptyField(field)
        }
    }

    private func validateIdentifier(
        _ value: String,
        field: String,
        kind: FlowIdentifierKind
    ) throws {
        do {
            try identifierValidator.validate(value, kind: kind)
        } catch {
            throw FlowArtifactEnvelopeValidationError.invalidIdentifier(
                field: field,
                value: value
            )
        }
    }
}

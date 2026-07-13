import Foundation

public struct XcircuiteArtifactEnvelopeValidator: Sendable {
    private let identifierValidator: XcircuiteIdentifierValidator

    public init(identifierValidator: XcircuiteIdentifierValidator = XcircuiteIdentifierValidator()) {
        self.identifierValidator = identifierValidator
    }

    public func validate(_ envelope: XcircuiteArtifactEnvelope) throws {
        guard envelope.schemaVersion == 1 else {
            throw XcircuiteArtifactEnvelopeValidationError.invalidSchemaVersion(envelope.schemaVersion)
        }
        try validateIdentifier(envelope.artifactID, field: "artifactID", kind: .artifactID)
        try validateNonEmpty(envelope.role, field: "role")
        try validateNonEmpty(envelope.reference.path, field: "reference.path")
        if envelope.reference.artifactID != envelope.artifactID {
            throw XcircuiteArtifactEnvelopeValidationError.artifactIDMismatch(
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

    private func validateProducer(_ producer: XcircuiteArtifactProducer?) throws {
        guard let producer else {
            return
        }
        try validateNonEmpty(producer.producerID, field: "producer.producerID")
    }

    private func validateDependencies(
        _ dependencies: [XcircuiteArtifactDependency],
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

    private func validateEvaluationSpec(_ spec: XcircuiteEvaluationSpec?) throws {
        guard let spec else {
            return
        }
        guard spec.schemaVersion == 1 else {
            throw XcircuiteArtifactEnvelopeValidationError.invalidSchemaVersion(spec.schemaVersion)
        }
        try validateNonEmpty(spec.specID, field: "evaluationSpec.specID")
        try validateNonEmpty(spec.objective, field: "evaluationSpec.objective")
        try validateConfidence(spec.confidence, field: "evaluationSpec.confidence")
        for criterion in spec.criteria {
            try validateNonEmpty(criterion.criterionID, field: "evaluationSpec.criteria.criterionID")
            try validateNonEmpty(criterion.channelID, field: "evaluationSpec.criteria.channelID")
        }
    }

    private func validateObservationSet(_ observationSet: XcircuiteObservationSet?) throws {
        guard let observationSet else {
            return
        }
        try validateNonEmpty(observationSet.observationSetID, field: "observationSet.observationSetID")
        try validateConfidence(observationSet.confidence, field: "observationSet.confidence")
        for channel in observationSet.channels {
            try validateNonEmpty(channel.channelID, field: "observationSet.channels.channelID")
            try validateConfidence(channel.confidence, field: "observationSet.channels.confidence")
        }
    }

    private func validateEvaluationResult(_ result: XcircuiteEvaluationResult?) throws {
        guard let result else {
            return
        }
        guard result.schemaVersion == 1 else {
            throw XcircuiteArtifactEnvelopeValidationError.invalidSchemaVersion(result.schemaVersion)
        }
        try validateNonEmpty(result.evaluationID, field: "evaluationResult.evaluationID")
        try validateNonEmpty(result.specID, field: "evaluationResult.specID")
        try validateUnitInterval(result.likelihood, field: "evaluationResult.likelihood")
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
            try validateConfidence(
                channelResult.confidence,
                field: "evaluationResult.channelResults.confidence"
            )
        }
        try validateFeedbackSignals(result.feedbackSignals, field: "evaluationResult.feedbackSignals")
    }

    private func validateFeedbackSignals(
        _ signals: [XcircuiteFeedbackSignal],
        field: String
    ) throws {
        for signal in signals {
            try validateNonEmpty(signal.signalID, field: "\(field).signalID")
            try validateNonEmpty(signal.summary, field: "\(field).summary")
            try validateConfidence(signal.confidence, field: "\(field).confidence")
        }
    }

    private func validateDelegationCertificate(
        _ certificate: XcircuiteDelegationCertificate?
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
        _ confidence: XcircuiteEvidenceConfidence?,
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
        if let posteriorVariance = confidence.posteriorVariance, posteriorVariance < 0 {
            throw XcircuiteArtifactEnvelopeValidationError.invalidPosteriorVariance(
                field: "\(field).posteriorVariance",
                value: posteriorVariance
            )
        }
    }

    private func validateUnitInterval(_ value: Double?, field: String) throws {
        guard let value else {
            return
        }
        guard value >= 0, value <= 1 else {
            throw XcircuiteArtifactEnvelopeValidationError.invalidConfidence(
                field: field,
                value: value
            )
        }
    }

    private func validateNonEmpty(_ value: String, field: String) throws {
        guard !value.isEmpty else {
            throw XcircuiteArtifactEnvelopeValidationError.emptyField(field)
        }
    }

    private func validateIdentifier(
        _ value: String,
        field: String,
        kind: XcircuiteIdentifierKind
    ) throws {
        do {
            try identifierValidator.validate(value, kind: kind)
        } catch {
            throw XcircuiteArtifactEnvelopeValidationError.invalidIdentifier(
                field: field,
                value: value
            )
        }
    }
}

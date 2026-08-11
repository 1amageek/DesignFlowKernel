import CircuiteFoundation
import Foundation

public struct FlowArtifactEnvelope: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var artifactID: String
    public var role: String
    public var stageID: String?
    public var binding: FlowArtifactBinding

    public var reference: ArtifactReference { binding.reference }
    public var producer: FlowArtifactProducer?
    public var inputs: [FlowArtifactDependency]
    public var dependencies: [FlowArtifactDependency]
    public var evaluationSpec: FlowEvaluationSpec?
    public var observationSet: FlowObservationSet?
    public var evaluationResult: FlowEvaluationResult?
    public var delegationCertificate: FlowDelegationCertificate?

    public init(
        schemaVersion: Int = 3,
        artifactID: String,
        role: String,
        stageID: String? = nil,
        binding: FlowArtifactBinding,
        producer: FlowArtifactProducer? = nil,
        inputs: [FlowArtifactDependency] = [],
        dependencies: [FlowArtifactDependency] = [],
        evaluationSpec: FlowEvaluationSpec? = nil,
        observationSet: FlowObservationSet? = nil,
        evaluationResult: FlowEvaluationResult? = nil,
        delegationCertificate: FlowDelegationCertificate? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.artifactID = artifactID
        self.role = role
        self.stageID = stageID
        self.binding = binding
        self.producer = producer
        self.inputs = inputs
        self.dependencies = dependencies
        self.evaluationSpec = evaluationSpec
        self.observationSet = observationSet
        self.evaluationResult = evaluationResult
        self.delegationCertificate = delegationCertificate
    }

}

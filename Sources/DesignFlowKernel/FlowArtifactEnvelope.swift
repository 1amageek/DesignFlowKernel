import CircuiteFoundation
import Foundation

public struct FlowArtifactEnvelope: Sendable, Hashable, Codable {
    @FlowSchemaVersion1 public var schemaVersion: Int
    public var artifactID: String
    public var role: String
    public var stageID: String?
    public var reference: ArtifactReference
    public var producer: FlowArtifactProducer?
    public var inputs: [FlowArtifactDependency]
    public var dependencies: [FlowArtifactDependency]
    public var evaluationSpec: FlowEvaluationSpec?
    public var observationSet: FlowObservationSet?
    public var evaluationResult: FlowEvaluationResult?
    public var delegationCertificate: FlowDelegationCertificate?

    public init(
        schemaVersion: Int = 1,
        artifactID: String,
        role: String,
        stageID: String? = nil,
        reference: ArtifactReference,
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
        self.reference = reference
        self.producer = producer
        self.inputs = inputs
        self.dependencies = dependencies
        self.evaluationSpec = evaluationSpec
        self.observationSet = observationSet
        self.evaluationResult = evaluationResult
        self.delegationCertificate = delegationCertificate
    }

}

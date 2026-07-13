import Foundation

public struct XcircuiteArtifactEnvelope: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var artifactID: String
    public var role: String
    public var stageID: String?
    public var reference: XcircuiteFileReference
    public var producer: XcircuiteArtifactProducer?
    public var inputs: [XcircuiteArtifactDependency]
    public var dependencies: [XcircuiteArtifactDependency]
    public var evaluationSpec: XcircuiteEvaluationSpec?
    public var observationSet: XcircuiteObservationSet?
    public var evaluationResult: XcircuiteEvaluationResult?
    public var delegationCertificate: XcircuiteDelegationCertificate?
    public var metadata: [String: XcircuiteJSONValue]

    public init(
        schemaVersion: Int = 1,
        artifactID: String,
        role: String,
        stageID: String? = nil,
        reference: XcircuiteFileReference,
        producer: XcircuiteArtifactProducer? = nil,
        inputs: [XcircuiteArtifactDependency] = [],
        dependencies: [XcircuiteArtifactDependency] = [],
        evaluationSpec: XcircuiteEvaluationSpec? = nil,
        observationSet: XcircuiteObservationSet? = nil,
        evaluationResult: XcircuiteEvaluationResult? = nil,
        delegationCertificate: XcircuiteDelegationCertificate? = nil,
        metadata: [String: XcircuiteJSONValue] = [:]
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
        self.metadata = metadata
    }
}

import Foundation

public struct FlowEvaluationContext: Sendable, Hashable, Codable {
    public struct Region: Sendable, Hashable, Codable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public var artifactID: String?
    public var artifactRole: String?
    public var stageID: String?
    public var gateID: String?
    public var profileID: String?
    public var domain: String?
    public var metricChannelID: String?
    public var observationChannelID: String?
    public var observationStatus: FlowObservationChannelStatus?
    public var source: String?
    public var category: String?
    public var kind: String?
    public var path: String?
    public var layer: String?
    public var ruleID: String?
    public var cornerID: String?
    public var parameterName: String?
    public var componentSignature: String?
    public var representativeRegion: String?
    public var layoutModel: String?
    public var schematicModel: String?
    public var layoutCount: Int?
    public var schematicCount: Int?
    public var minimumValue: Double?
    public var maximumValue: Double?
    public var relativeSpread: Double?
    public var minimumCornerID: String?
    public var maximumCornerID: String?
    public var parasiticIRArtifactID: String?
    public var spefRoundTripArtifactID: String?
    public var required: Bool?
    public var requiredValue: Double?
    public var bucketIndex: Int?
    public var activeCount: Int?
    public var waivedCount: Int?
    public var relatedShapeIDs: [String]
    public var relatedNetIDs: [String]
    public var layoutPorts: [String]
    public var schematicPorts: [String]
    public var suggestedActions: [String]
    public var maximumMeasuredValue: Double?
    public var region: Region?

    public init(
        artifactID: String? = nil,
        artifactRole: String? = nil,
        stageID: String? = nil,
        gateID: String? = nil,
        profileID: String? = nil,
        domain: String? = nil,
        metricChannelID: String? = nil,
        observationChannelID: String? = nil,
        observationStatus: FlowObservationChannelStatus? = nil,
        source: String? = nil,
        category: String? = nil,
        kind: String? = nil,
        path: String? = nil,
        layer: String? = nil,
        ruleID: String? = nil,
        cornerID: String? = nil,
        parameterName: String? = nil,
        componentSignature: String? = nil,
        representativeRegion: String? = nil,
        layoutModel: String? = nil,
        schematicModel: String? = nil,
        layoutCount: Int? = nil,
        schematicCount: Int? = nil,
        minimumValue: Double? = nil,
        maximumValue: Double? = nil,
        relativeSpread: Double? = nil,
        minimumCornerID: String? = nil,
        maximumCornerID: String? = nil,
        parasiticIRArtifactID: String? = nil,
        spefRoundTripArtifactID: String? = nil,
        required: Bool? = nil,
        requiredValue: Double? = nil,
        bucketIndex: Int? = nil,
        activeCount: Int? = nil,
        waivedCount: Int? = nil,
        relatedShapeIDs: [String] = [],
        relatedNetIDs: [String] = [],
        layoutPorts: [String] = [],
        schematicPorts: [String] = [],
        suggestedActions: [String] = [],
        maximumMeasuredValue: Double? = nil,
        region: Region? = nil
    ) {
        self.artifactID = artifactID
        self.artifactRole = artifactRole
        self.stageID = stageID
        self.gateID = gateID
        self.profileID = profileID
        self.domain = domain
        self.metricChannelID = metricChannelID
        self.observationChannelID = observationChannelID
        self.observationStatus = observationStatus
        self.source = source
        self.category = category
        self.kind = kind
        self.path = path
        self.layer = layer
        self.ruleID = ruleID
        self.cornerID = cornerID
        self.parameterName = parameterName
        self.componentSignature = componentSignature
        self.representativeRegion = representativeRegion
        self.layoutModel = layoutModel
        self.schematicModel = schematicModel
        self.layoutCount = layoutCount
        self.schematicCount = schematicCount
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.relativeSpread = relativeSpread
        self.minimumCornerID = minimumCornerID
        self.maximumCornerID = maximumCornerID
        self.parasiticIRArtifactID = parasiticIRArtifactID
        self.spefRoundTripArtifactID = spefRoundTripArtifactID
        self.required = required
        self.requiredValue = requiredValue
        self.bucketIndex = bucketIndex
        self.activeCount = activeCount
        self.waivedCount = waivedCount
        self.relatedShapeIDs = relatedShapeIDs
        self.relatedNetIDs = relatedNetIDs
        self.layoutPorts = layoutPorts
        self.schematicPorts = schematicPorts
        self.suggestedActions = suggestedActions
        self.maximumMeasuredValue = maximumMeasuredValue
        self.region = region
    }
}

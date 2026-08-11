import CircuiteFoundation
import Foundation

/// Binds location-independent artifact identity to an independently resolved
/// materialization for flow execution, review, and resume.
public struct FlowArtifactBinding: Sendable, Hashable, Codable {
    public let logicalID: String
    public let reference: ArtifactReference
    public let availability: ArtifactAvailability
    public let producer: ProducerIdentity?

    public init(
        logicalID: String,
        reference: ArtifactReference,
        availability: ArtifactAvailability,
        producer: ProducerIdentity? = nil
    ) throws {
        do {
            try FlowIdentifierValidator().validate(logicalID, kind: .artifactID)
        } catch {
            throw FlowArtifactBindingError.invalidLogicalID(logicalID)
        }
        guard availability.artifactID == reference.id else {
            throw FlowArtifactBindingError.availabilityIdentityMismatch
        }
        self.logicalID = logicalID
        self.reference = reference
        self.availability = availability
        self.producer = producer
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            logicalID: container.decode(String.self, forKey: .logicalID),
            reference: container.decode(ArtifactReference.self, forKey: .reference),
            availability: container.decode(ArtifactAvailability.self, forKey: .availability),
            producer: container.decodeIfPresent(ProducerIdentity.self, forKey: .producer)
        )
    }

    public var descriptor: ArtifactDescriptor { reference.descriptor }
    public var role: ArtifactRole { descriptor.role }
    public var kind: ArtifactKind { descriptor.kind }
    public var format: ArtifactFormat { descriptor.format }

    public func requireLocalRelativePath() throws -> ArtifactRelativePath {
        guard case .local(_, _, let relativePath) = availability else {
            throw FlowArtifactBindingError.localAvailabilityRequired(logicalID: logicalID)
        }
        return relativePath
    }

    public func requireLocalRootID() throws -> ArtifactRootID {
        guard case .local(_, let rootID, _) = availability else {
            throw FlowArtifactBindingError.localAvailabilityRequired(logicalID: logicalID)
        }
        return rootID
    }

    public var availabilityDescription: String {
        switch availability {
        case .local(_, let rootID, let relativePath):
            "local:\(rootID.rawValue)/\(relativePath.stringValue)"
        case .service(_, let resource):
            "service:\(String(describing: resource))"
        }
    }
}

import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public struct FlowCandidatePromotionAuthorization: Sendable, Hashable, Codable {
    public let authorizationID: String
    public let decisionID: String
    public let decisionDigest: ContentDigest
    public let databaseID: DesignDatabaseID
    public let targetReferenceName: String
    public let expectedGeneration: UInt64
    public let expectedRevision: DesignRevisionReference?
    public let desiredRevision: DesignRevisionReference
    public let semanticGraphDigest: ContentDigest
    public let evidenceBindingDigest: ContentDigest
    public let issuedAt: Date
    public let expiresAt: Date?
    public let authorizationDigest: ContentDigest

    public init(
        authorizationID: String,
        decisionID: String,
        decisionDigest: ContentDigest,
        databaseID: DesignDatabaseID,
        targetReferenceName: String,
        expectedGeneration: UInt64,
        expectedRevision: DesignRevisionReference?,
        desiredRevision: DesignRevisionReference,
        semanticGraphDigest: ContentDigest,
        evidenceBindingDigest: ContentDigest,
        issuedAt: Date,
        expiresAt: Date?,
        authorizationDigest: ContentDigest
    ) {
        self.authorizationID = authorizationID
        self.decisionID = decisionID
        self.decisionDigest = decisionDigest
        self.databaseID = databaseID
        self.targetReferenceName = targetReferenceName
        self.expectedGeneration = expectedGeneration
        self.expectedRevision = expectedRevision
        self.desiredRevision = desiredRevision
        self.semanticGraphDigest = semanticGraphDigest
        self.evidenceBindingDigest = evidenceBindingDigest
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.authorizationDigest = authorizationDigest
    }

    public static func contentAddressed(
        authorizationID: String,
        decisionID: String,
        decisionDigest: ContentDigest,
        databaseID: DesignDatabaseID,
        targetReferenceName: String,
        expectedGeneration: UInt64,
        expectedRevision: DesignRevisionReference?,
        desiredRevision: DesignRevisionReference,
        semanticGraphDigest: ContentDigest,
        evidenceBindingDigest: ContentDigest,
        issuedAt: Date,
        expiresAt: Date?,
        using digester: any ContentDigesting = SHA256ContentDigester()
    ) throws -> Self {
        let digest = try FlowCandidatePromotionAuthorizationDigest.make(
            authorizationID: authorizationID,
            decisionID: decisionID,
            decisionDigest: decisionDigest,
            databaseID: databaseID,
            targetReferenceName: targetReferenceName,
            expectedGeneration: expectedGeneration,
            expectedRevision: expectedRevision,
            desiredRevision: desiredRevision,
            semanticGraphDigest: semanticGraphDigest,
            evidenceBindingDigest: evidenceBindingDigest,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            using: digester
        )
        return Self(
            authorizationID: authorizationID,
            decisionID: decisionID,
            decisionDigest: decisionDigest,
            databaseID: databaseID,
            targetReferenceName: targetReferenceName,
            expectedGeneration: expectedGeneration,
            expectedRevision: expectedRevision,
            desiredRevision: desiredRevision,
            semanticGraphDigest: semanticGraphDigest,
            evidenceBindingDigest: evidenceBindingDigest,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            authorizationDigest: digest
        )
    }
}

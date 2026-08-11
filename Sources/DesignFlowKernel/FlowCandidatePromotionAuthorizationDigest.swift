import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public enum FlowCandidatePromotionAuthorizationDigest {
    public static func make(
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
    ) throws -> ContentDigest {
        let projection = Projection(
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
            expiresAt: expiresAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try digester.digest(data: encoder.encode(projection))
    }

    private struct Projection: Encodable {
        let authorizationID: String
        let decisionID: String
        let decisionDigest: ContentDigest
        let databaseID: DesignDatabaseID
        let targetReferenceName: String
        let expectedGeneration: UInt64
        let expectedRevision: DesignRevisionReference?
        let desiredRevision: DesignRevisionReference
        let semanticGraphDigest: ContentDigest
        let evidenceBindingDigest: ContentDigest
        let issuedAt: Date
        let expiresAt: Date?
    }
}

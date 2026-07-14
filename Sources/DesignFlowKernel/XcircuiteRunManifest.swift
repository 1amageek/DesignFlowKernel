import Foundation

public struct XcircuiteRunManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let runID: String
    public internal(set) var status: XcircuiteRunStatus
    public internal(set) var revision: Int
    public let actor: XcircuiteRunActionActor
    public let intent: String?
    public let parentRunID: String?
    public let createdAt: Date
    public internal(set) var updatedAt: Date
    public internal(set) var startedAt: Date?
    public internal(set) var finishedAt: Date?
    public internal(set) var artifacts: [XcircuiteFileReference]

    public init(
        runID: String,
        status: XcircuiteRunStatus,
        revision: Int = 0,
        actor: XcircuiteRunActionActor,
        intent: String? = nil,
        parentRunID: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        artifacts: [XcircuiteFileReference] = []
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.status = status
        self.revision = revision
        self.actor = actor
        self.intent = intent
        self.parentRunID = parentRunID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.artifacts = artifacts
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case status
        case revision
        case actor
        case intent
        case parentRunID
        case createdAt
        case updatedAt
        case startedAt
        case finishedAt
        case artifacts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected run manifest schema version \(Self.currentSchemaVersion)."
            )
        }
        runID = try container.decode(String.self, forKey: .runID)
        status = try container.decode(XcircuiteRunStatus.self, forKey: .status)
        revision = try container.decode(Int.self, forKey: .revision)
        actor = try container.decode(XcircuiteRunActionActor.self, forKey: .actor)
        intent = try container.decodeIfPresent(String.self, forKey: .intent)
        parentRunID = try container.decodeIfPresent(String.self, forKey: .parentRunID)
        createdAt = try Self.decodeRequiredTimestamp(from: container, forKey: .createdAt)
        updatedAt = try Self.decodeRequiredTimestamp(from: container, forKey: .updatedAt)
        startedAt = try Self.decodeTimestamp(from: container, forKey: .startedAt)
        finishedAt = try Self.decodeTimestamp(from: container, forKey: .finishedAt)
        artifacts = try container.decode([XcircuiteFileReference].self, forKey: .artifacts)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(runID, forKey: .runID)
        try container.encode(status, forKey: .status)
        try container.encode(revision, forKey: .revision)
        try container.encode(actor, forKey: .actor)
        try container.encodeIfPresent(intent, forKey: .intent)
        try container.encodeIfPresent(parentRunID, forKey: .parentRunID)
        try Self.encodeTimestamp(createdAt, to: &container, forKey: .createdAt)
        try Self.encodeTimestamp(updatedAt, to: &container, forKey: .updatedAt)
        try Self.encodeTimestamp(startedAt, to: &container, forKey: .startedAt)
        try Self.encodeTimestamp(finishedAt, to: &container, forKey: .finishedAt)
        try container.encode(artifacts, forKey: .artifacts)
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw XcircuiteWorkspaceError.invalidRunManifest(
                runID: runID,
                reason: "schemaVersion must be \(Self.currentSchemaVersion)."
            )
        }
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        if let parentRunID {
            try XcircuiteIdentifierValidator().validate(parentRunID, kind: .runID)
            guard parentRunID != runID else {
                throw XcircuiteWorkspaceError.invalidRunManifest(
                    runID: runID,
                    reason: "parentRunID must identify a different run."
                )
            }
        }
        guard revision >= 0 else {
            throw XcircuiteWorkspaceError.invalidRunManifest(
                runID: runID,
                reason: "revision must be non-negative."
            )
        }
        guard !actor.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteWorkspaceError.invalidRunManifest(
                runID: runID,
                reason: "actor.identifier must not be empty."
            )
        }
        if let intent {
            guard !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteWorkspaceError.invalidRunManifest(
                    runID: runID,
                    reason: "intent must be absent or non-empty."
                )
            }
        }
        guard updatedAt >= createdAt else {
            throw XcircuiteWorkspaceError.invalidRunManifest(
                runID: runID,
                reason: "updatedAt must not precede createdAt."
            )
        }
        if let startedAt {
            guard startedAt >= createdAt else {
                throw XcircuiteWorkspaceError.invalidRunManifest(
                    runID: runID,
                    reason: "startedAt must not precede createdAt."
                )
            }
        }
        if let finishedAt {
            guard let startedAt, finishedAt >= startedAt, updatedAt >= finishedAt else {
                throw XcircuiteWorkspaceError.invalidRunManifest(
                    runID: runID,
                    reason: "finishedAt must follow startedAt and must not follow updatedAt."
                )
            }
        }
        var artifactPaths: Set<String> = []
        var artifactIDs: Set<String> = []
        for artifact in artifacts {
            try Self.validateArtifactPath(artifact.path, runID: runID)
            guard artifactPaths.insert(artifact.path).inserted else {
                throw XcircuiteWorkspaceError.invalidRunManifest(
                    runID: runID,
                    reason: "artifact path '\(artifact.path)' must be unique."
                )
            }
            if let artifactID = artifact.artifactID {
                try XcircuiteIdentifierValidator().validate(artifactID, kind: .artifactID)
                guard artifactIDs.insert(artifactID).inserted else {
                    throw XcircuiteWorkspaceError.invalidRunManifest(
                        runID: runID,
                        reason: "artifactID '\(artifactID)' must be unique."
                    )
                }
            }
        }

        switch status {
        case .created:
            guard startedAt == nil, finishedAt == nil else {
                throw lifecycleTimestampError("created runs cannot have startedAt or finishedAt.")
            }
        case .running:
            guard startedAt != nil, finishedAt == nil else {
                throw lifecycleTimestampError("running runs require startedAt and cannot have finishedAt.")
            }
        case .succeeded, .failed, .cancelled, .blocked, .partial:
            guard startedAt != nil, finishedAt != nil else {
                throw lifecycleTimestampError("terminal runs require startedAt and finishedAt.")
            }
        }
    }

    private func lifecycleTimestampError(_ reason: String) -> XcircuiteWorkspaceError {
        .invalidRunManifest(runID: runID, reason: reason)
    }

    private static func validateArtifactPath(_ path: String, runID: String) throws {
        do {
            try XcircuiteWorkspace.validateProjectRelativePath(path)
        } catch {
            throw XcircuiteWorkspaceError.invalidRunManifest(
                runID: runID,
                reason: "artifact path '\(path)' must be project-relative."
            )
        }
    }

    private static func decodeRequiredTimestamp(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date {
        guard let timestamp = try decodeTimestamp(from: container, forKey: key) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "A lifecycle timestamp is required."
            )
        }
        return timestamp
    }

    private static func decodeTimestamp(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else {
            return nil
        }
        let value = try container.decode(String.self, forKey: key)
        do {
            return try timestampStyle.parse(value)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Expected an ISO 8601 timestamp with fractional seconds."
            )
        }
    }

    private static func encodeTimestamp(
        _ date: Date?,
        to container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        guard let date else {
            return
        }
        try container.encode(timestampStyle.format(date), forKey: key)
    }

    private static var timestampStyle: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    }
}

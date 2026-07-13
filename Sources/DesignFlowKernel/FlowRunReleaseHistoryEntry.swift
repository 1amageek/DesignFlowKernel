import Foundation
import XcircuitePackage

public struct FlowRunReleaseHistoryEntry: Sendable, Hashable, Codable {
    public var sequence: Int
    public var entryID: String
    public var runID: String
    public var recordedAt: String
    public var qualificationDigest: String
    public var previousEntrySHA256: String?
    public var entrySHA256: String

    public init(
        sequence: Int,
        entryID: String,
        runID: String,
        recordedAt: String,
        qualificationDigest: String,
        previousEntrySHA256: String?,
        entrySHA256: String
    ) {
        self.sequence = sequence
        self.entryID = entryID
        self.runID = runID
        self.recordedAt = recordedAt
        self.qualificationDigest = qualificationDigest
        self.previousEntrySHA256 = previousEntrySHA256
        self.entrySHA256 = entrySHA256
    }

    public func computedSHA256(using hasher: XcircuiteHasher = XcircuiteHasher()) throws -> String {
        hasher.sha256(data: try canonicalHashMaterial())
    }

    public var isStructurallyValid: Bool {
        sequence > 0
            && !entryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !recordedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !qualificationDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Self.isSHA256(entrySHA256)
            && (previousEntrySHA256 == nil || Self.isSHA256(previousEntrySHA256 ?? ""))
    }

    private struct HashMaterial: Encodable {
        var sequence: Int
        var entryID: String
        var runID: String
        var recordedAt: String
        var qualificationDigest: String
        var previousEntrySHA256: String?
    }

    private func canonicalHashMaterial() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(HashMaterial(
            sequence: sequence,
            entryID: entryID,
            runID: runID,
            recordedAt: recordedAt,
            qualificationDigest: qualificationDigest,
            previousEntrySHA256: previousEntrySHA256
        ))
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { character in
            character.isNumber || ("a"..."f").contains(character) || ("A"..."F").contains(character)
        }
    }
}

import Foundation
import CircuiteFoundation

private enum LegacyArtifactProjectionError: Error {
    case byteCountOutOfRange(String)
}

/// Storage-boundary projection used by the frozen run-ledger record format.
/// New flow results remain in the Foundation artifact model until persistence.
extension ArtifactReference {
    public func legacyXcircuiteReference() throws -> XcircuiteFileReference {
        let kind = XcircuiteFileKind(rawValue: legacyKindRawValue) ?? .other
        let format = XcircuiteFileFormat(rawValue: legacyFormatRawValue) ?? .unknown
        guard byteCount <= UInt64(Int64.max) else {
            throw LegacyArtifactProjectionError.byteCountOutOfRange(path)
        }
        return XcircuiteFileReference(
            artifactID: artifactID,
            path: path,
            kind: kind,
            format: format,
            sha256: sha256,
            byteCount: Int64(byteCount),
            producedByRunID: producedByRunIDFromPath
        )
    }

    /// Legacy run records carried the run identifier separately from the
    /// canonical Foundation reference. Preserve it when projecting a
    /// run-relative artifact back into the frozen storage record.
    private var producedByRunIDFromPath: String? {
        let components = path.split(separator: "/").map(String.init)
        guard components.count > 2,
              components[0] == ".xcircuite",
              components[1] == "runs" else {
            return nil
        }
        return components[2]
    }

    private var legacyKindRawValue: String {
        switch kind.rawValue {
        case "power-intent": return "powerIntent"
        case "timing-library": return "timingLibrary"
        case "test-pattern": return "testPattern"
        case "rule-deck": return "ruleDeck"
        case "design-diff": return "designDiff"
        case "parasitics": return "parasitic"
        default: return kind.rawValue
        }
    }

    private var legacyFormatRawValue: String {
        switch format.rawValue {
        case "system-verilog": return "SYSTEM_VERILOG"
        default: return format.rawValue.uppercased()
        }
    }
}

extension XcircuiteFileReference {
    /// Decode-only projection from the frozen pre-Foundation artifact shape.
    /// Callers must not persist the returned legacy value again.
    func foundationArtifactReference(role: ArtifactRole) throws -> ArtifactReference {
        guard let sha256, !sha256.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Legacy artifact is missing sha256: \(path)")
            )
        }
        guard let byteCount, byteCount >= 0 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Legacy artifact has an invalid byte count: \(path)")
            )
        }
        let location: ArtifactLocation
        if path.hasPrefix("/") {
            location = try ArtifactLocation(fileURL: URL(filePath: path))
        } else {
            location = try ArtifactLocation(workspaceRelativePath: path)
        }
        let kind = try ArtifactKind(rawValue: foundationKindRawValue)
        let format = try ArtifactFormat(rawValue: foundationFormatRawValue)
        let digest = try ContentDigest(algorithm: .sha256, hexadecimalValue: sha256)
        let id = try artifactID.map { try ArtifactID(rawValue: $0) }
        return ArtifactReference(
            id: id,
            locator: ArtifactLocator(
                location: location,
                role: role,
                kind: kind,
                format: format
            ),
            digest: digest,
            byteCount: UInt64(byteCount)
        )
    }

    private var foundationKindRawValue: String {
        switch kind {
        case .powerIntent: return "power-intent"
        case .timingLibrary: return "timing-library"
        case .testPattern: return "test-pattern"
        case .ruleDeck: return "rule-deck"
        case .designDiff: return "design-diff"
        case .parasitic: return "parasitics"
        default: return kind.rawValue
        }
    }

    private var foundationFormatRawValue: String {
        switch format {
        case .systemVerilog: return "system-verilog"
        default: return format.rawValue.lowercased()
        }
    }
}

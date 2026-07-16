import Foundation

public enum FlowArtifactEnvelopeValidationError: Error, LocalizedError, Equatable {
    case invalidSchemaVersion(Int)
    case emptyField(String)
    case invalidIdentifier(field: String, value: String)
    case artifactIDMismatch(envelopeArtifactID: String, referenceArtifactID: String)
    case negativeByteCount(Int64)
    case referenceIntegrityFailed(path: String, message: String)
    case invalidConfidence(field: String, value: Double)
    case invalidPosteriorVariance(field: String, value: Double)
    case nonFiniteNumericValue(field: String, value: Double)

    public var errorDescription: String? {
        switch self {
        case .invalidSchemaVersion(let version):
            "Artifact envelope schema version is not supported: \(version)."
        case .emptyField(let field):
            "Artifact envelope field must not be empty: \(field)."
        case .invalidIdentifier(let field, let value):
            "Artifact envelope field has an invalid identifier: \(field)=\(value)."
        case .artifactIDMismatch(let envelopeArtifactID, let referenceArtifactID):
            "Artifact envelope ID \(envelopeArtifactID) does not match file reference artifact ID \(referenceArtifactID)."
        case .negativeByteCount(let byteCount):
            "Artifact envelope file reference byte count must be non-negative: \(byteCount)."
        case .referenceIntegrityFailed(let path, let message):
            "Artifact envelope file reference integrity failed for \(path): \(message)"
        case .invalidConfidence(let field, let value):
            "Artifact envelope confidence value must be in 0...1: \(field)=\(value)."
        case .invalidPosteriorVariance(let field, let value):
            "Artifact envelope posterior variance must be non-negative: \(field)=\(value)."
        case .nonFiniteNumericValue(let field, let value):
            "Artifact envelope numeric evidence must be finite: \(field)=\(value)."
        }
    }
}

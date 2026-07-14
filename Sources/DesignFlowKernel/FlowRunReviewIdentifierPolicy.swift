import Foundation

struct FlowRunReviewIdentifierPolicy: Sendable {
    private let validator: XcircuiteIdentifierValidator
    private let hasher: XcircuiteHasher

    init(
        validator: XcircuiteIdentifierValidator = XcircuiteIdentifierValidator(),
        hasher: XcircuiteHasher = XcircuiteHasher()
    ) {
        self.validator = validator
        self.hasher = hasher
    }

    func isValidRunID(_ value: String) -> Bool {
        isValidIdentifier(value, kind: .runID)
    }

    func isValidStageID(_ value: String) -> Bool {
        isValidIdentifier(value, kind: .stageID)
    }

    func isValidArtifactID(_ value: String) -> Bool {
        isValidIdentifier(value, kind: .artifactID)
    }

    func safeStageScopedID(stageID: String, suffix: String) -> String {
        let stageComponent = isValidStageID(stageID)
            ? stageID
            : "invalid-stage-\(digestPrefix(for: stageID))"
        return "\(stageComponent)-\(safeComponent(suffix, fallbackPrefix: "item"))"
    }

    func safeComponent(_ value: String, fallbackPrefix: String) -> String {
        if isValidArtifactID(value) {
            return value
        }
        return "\(fallbackPrefix)-\(digestPrefix(for: value))"
    }

    func stageStatusRef(runID: String, stageID: String?) -> String? {
        guard let stageID, isValidRunID(runID), isValidStageID(stageID) else {
            return nil
        }
        return "\(XcircuiteWorkspace.directoryName)/runs/\(runID)/stages/\(stageID)/result.json"
    }

    func approvalArtifactPath(runID: String, stageID: String) -> String? {
        guard isValidRunID(runID), isValidStageID(stageID) else {
            return nil
        }
        return "\(XcircuiteWorkspace.directoryName)/runs/\(runID)/approvals/\(stageID).json"
    }

    func invalidStageIdentifierIntegrity(_ stageID: String) -> FlowRunReviewArtifactIntegrity {
        FlowRunReviewArtifactIntegrity(
            status: .invalidIdentifier,
            message: "Stage identifier is not safe for artifact path, review item, or replay reference synthesis: \(stageID)"
        )
    }

    func invalidArtifactIdentifierIntegrity(_ artifactID: String) -> FlowRunReviewArtifactIntegrity {
        FlowRunReviewArtifactIntegrity(
            status: .invalidIdentifier,
            message: "Artifact identifier is not safe for review or handoff reference synthesis: \(artifactID)"
        )
    }

    private func isValidIdentifier(_ value: String, kind: XcircuiteIdentifierKind) -> Bool {
        do {
            try validator.validate(value, kind: kind)
            return true
        } catch {
            return false
        }
    }

    private func digestPrefix(for value: String) -> String {
        String(hasher.sha256(data: Data(value.utf8)).prefix(12))
    }
}

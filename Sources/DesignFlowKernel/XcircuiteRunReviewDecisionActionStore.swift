import Foundation

extension XcircuitePackageStore {
    @discardableResult
    public func appendReviewDecisionAction(
        _ request: XcircuiteRunReviewDecisionActionRequest,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteRunActionRecord {
        let validator = XcircuiteIdentifierValidator()
        try validator.validate(request.runID, kind: .runID)
        if let stageID = request.stageID {
            try validator.validate(stageID, kind: .stageID)
        }

        let record = XcircuiteRunActionRecord(
            actionID: request.actionID,
            runID: request.runID,
            stageID: request.stageID,
            actor: request.actor,
            actionKind: request.decisionKind.rawValue,
            status: request.status,
            inputs: try request.inputs.map { try $0.legacyXcircuiteReference() },
            outputs: try request.outputs.map { try $0.legacyXcircuiteReference() },
            diagnostics: request.diagnostics,
            metadata: reviewDecisionMetadata(for: request),
            createdAt: request.createdAt
        )
        try appendRunAction(record, inProjectAt: projectRoot)
        return record
    }

    public func loadReviewDecisionActions(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> [XcircuiteRunReviewDecisionAction] {
        var decisions: [XcircuiteRunReviewDecisionAction] = []
        for record in try loadRunActions(runID: runID, inProjectAt: projectRoot) {
            if let decision = try XcircuiteRunReviewDecisionAction(record: record) {
                decisions.append(decision)
            }
        }
        return decisions
    }

    public func loadLatestReviewDecisionAction(
        runID: String,
        decisionKind: XcircuiteRunReviewDecisionActionKind? = nil,
        targetID: String? = nil,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteRunReviewDecisionAction? {
        try loadReviewDecisionActions(runID: runID, inProjectAt: projectRoot)
            .last { decision in
                (decisionKind == nil || decision.decisionKind == decisionKind)
                    && (targetID == nil || decision.targetID == targetID)
            }
    }

    private func reviewDecisionMetadata(
        for request: XcircuiteRunReviewDecisionActionRequest
    ) -> [String: XcircuiteJSONValue] {
        var metadata = request.metadata
        metadata["decisionKind"] = .string(request.decisionKind.rawValue)
        metadata["decision"] = .string(request.decision)
        metadata["targetID"] = .string(request.targetID)
        metadata["reason"] = .string(request.reason)
        if let targetPath = request.targetPath {
            metadata["targetPath"] = .string(targetPath)
        }
        return metadata
    }
}

import CircuiteFoundation

public struct FlowRunActionReducer: Sendable {
    public init() {}

    public func appending(
        _ action: FlowRunActionRecord,
        to ledger: FlowRunLedger
    ) throws -> FlowRunLedger {
        guard action.runID == ledger.runID else {
            throw FlowRunLedgerPersistenceError.runIdentifierMismatch(
                requested: action.runID,
                stored: ledger.runID
            )
        }
        if let existing = ledger.actions.first(where: { $0.actionID == action.actionID }) {
            guard existing == action else {
                throw FlowRunLedgerPersistenceError.duplicateActionID(
                    runID: action.runID,
                    actionID: action.actionID
                )
            }
            return ledger
        }
        let retainedReferences = Set(
            ledger.artifacts + ledger.actions.flatMap(\.outputs)
        )
        if let unretained = (action.inputs + action.outputs).first(where: {
            !retainedReferences.contains($0)
        }) {
            throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                runID: action.runID,
                path: unretained.path
            )
        }

        var updated = ledger
        updated.actions.append(action)
        if let selection = try FlowRunSuggestedActionSelection(record: action) {
            updated.suggestedActionSelections.append(selection)
        }
        return updated
    }
}

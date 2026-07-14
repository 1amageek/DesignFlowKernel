import Foundation

/// Composition-root defaults for local command-line use.
///
/// Production hosts should inject their workspace storage explicitly. Keeping
/// filesystem construction in one place prevents flow components from
/// depending on a concrete store.
public enum DesignFlowStorageDefaults {
    public static func makeExecutionStorage() -> any FlowExecutionStorage {
        XcircuiteWorkspaceStore()
    }

    public static func makeLedgerStorage() -> any XcircuiteRunLedgerStoring {
        XcircuiteWorkspaceStore()
    }
}

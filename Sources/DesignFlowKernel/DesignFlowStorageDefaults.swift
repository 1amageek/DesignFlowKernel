import Foundation

/// Transitional composition-root defaults for local command-line use.
///
/// Production hosts should inject their workspace storage explicitly. Keeping
/// the legacy filesystem construction in one place prevents flow components
/// from depending on a concrete store while the `.xcircuite` migration is in
/// progress.
public enum DesignFlowStorageDefaults {
    public static func makeExecutionStorage() -> any FlowExecutionStorage {
        XcircuitePackageStore()
    }

    public static func makeLedgerStorage() -> any XcircuiteRunLedgerStoring {
        XcircuitePackageStore()
    }
}

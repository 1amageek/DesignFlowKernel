# DesignFlowKernel goal status

| Goal | Status | Evidence |
|---|---|---|
| Depend on CircuiteFoundation | Complete | `Package.swift` and target dependency updated. |
| Foundation Engine boundary | Complete | `FlowEngine`, `FlowEngineRequest`, `DefaultFlowEngine`. |
| Shared result contracts | Complete | `FlowRunResult` directly conforms to `ArtifactProducing`, `EvidenceProviding`, and `DiagnosticReporting` while carrying mandatory execution provenance. |
| Preserve run lifecycle ownership | Complete | Existing orchestrator owns lifecycle; `FlowRunLedgerPersisting` defines the injectable async storage seam. |
| Foundation-first artifact persistence | Complete | `FlowArtifactPersisting` accepts and returns canonical `ArtifactReference` values; `FlowRunInfrastructure` composes artifact and ledger-loading capabilities without selecting a filesystem. |
| Resume failure history | Complete | setup failure after transition to `running` appends typed failure state while preserving prior stages and toolchain records |
| Document implementation contract | Complete | README, DESIGN.md, REQUIREMENTS.md. |
| Build and tests | Passed for reviewed scope | `DesignFlowKernel` builds; 175 Swift Testing cases pass through the timeout-bounded Xcode package test scheme. |

## Handoff scope

The package exposes storage contracts that keep concrete namespace and
filesystem details outside the flow kernel. Callers provide an implementation
through the protocol; unsupported record shapes fail during decoding.

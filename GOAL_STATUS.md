# DesignFlowKernel goal status

| Goal | Status | Evidence |
|---|---|---|
| Depend on CircuiteFoundation | Complete | `Package.swift` and target dependency updated. |
| Foundation Engine boundary | Complete | `FlowEngine`, `FlowEngineRequest`, `DefaultFlowEngine`. |
| Shared result contracts | Complete | `FlowRunResult` directly conforms to `ArtifactProducing`, `EvidenceProviding`, and `DiagnosticReporting` while carrying mandatory execution provenance. |
| Preserve run lifecycle ownership | Complete | Existing orchestrator owns lifecycle; `FlowRunLedgerPersisting` defines the injectable async storage seam. |
| Foundation-first artifact persistence | Complete | `FlowArtifactPersisting` accepts and returns canonical `ArtifactReference` values; `FlowRunInfrastructure` composes the runtime persistence capabilities without selecting a filesystem. |
| Document implementation contract | Complete | README, DESIGN.md, REQUIREMENTS.md. |
| Build and tests | Passed | `swift build`; 141 Swift Testing cases pass with `swift test`. |

## Handoff scope

The package exposes storage contracts that keep concrete namespace and
filesystem details outside the flow kernel. Callers provide an implementation
through the protocol; unsupported record shapes fail during decoding.

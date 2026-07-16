# DesignFlowKernel goal status

| Goal | Status | Evidence |
|---|---|---|
| Depend on CircuiteFoundation | Complete | `Package.swift` and target dependency updated. |
| Foundation Engine boundary | Complete | `FlowEngine`, `FlowEngineRequest`, `DefaultFlowEngine`. |
| Foundation evidence boundary | Complete | `DesignFlowFoundationEvidence` is a Codable/Hashable `ArtifactProducing`, `EvidenceProviding` and `DiagnosticReporting` projection with deterministic Foundation identity. |
| Preserve run lifecycle ownership | Complete | Existing orchestrator owns lifecycle; `FlowRunLedgerPersisting` defines the injectable async storage seam. |
| Foundation-first artifact persistence | Complete | `FlowArtifactPersisting` accepts and returns canonical `ArtifactReference` values; `FlowRunInfrastructure` composes the runtime persistence capabilities without selecting a filesystem. |
| Document implementation contract | Complete | README, DESIGN.md, REQUIREMENTS.md. |
| Build | Passed | `swift build` after adding the persistence contract. |

## Handoff scope

The package exposes the storage contract needed to keep concrete `.xcircuite`
filesystem details outside the flow kernel. Callers provide an implementation
through the protocol; unsupported record shapes fail during decoding.

# DesignFlowKernel goal status

| Goal | Status | Evidence |
|---|---|---|
| Depend on CircuiteFoundation | Complete | `Package.swift` and target dependency updated. |
| Foundation Engine boundary | Complete | `FlowEngine`, `FlowEngineRequest`, `DefaultFlowEngine`. |
| Foundation evidence boundary | Complete | `DesignFlowFoundationEvidence` is a Codable/Hashable `ArtifactProducing`, `EvidenceProviding` and `DiagnosticReporting` projection with deterministic legacy identity handling. |
| Preserve run lifecycle ownership | Complete | Existing orchestrator owns lifecycle; `FlowRunLedgerPersisting` defines the injectable async storage seam. |
| Foundation-first execution storage | Complete | `FlowExecutionStorage.makeArtifactReference` and `registerArtifact` expose canonical `ArtifactReference` values; progress artifacts use the new API, while legacy entry points are deprecated for migration. |
| Document implementation contract | Complete | README, DESIGN.md, REQUIREMENTS.md. |
| Build | Passed | `swift build` after adding the persistence contract. |

## Handoff scope

The package exposes the storage contract needed to remove the concrete
`Xcircuite workspace` dependency. Existing legacy callers remain during the
staged migration; the compatibility package is not a new API surface.

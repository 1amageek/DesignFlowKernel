# DesignFlowKernel requirements

## Required capabilities

| Capability | Requirement |
|---|---|
| Engine boundary | Expose flow execution through `CircuiteFoundation.Engine`. |
| Stage execution | Accept independently implemented `FlowStageExecutor` values. |
| Trust gates | Evaluate tool qualification before a stage executes. |
| Approval | Persist approval decisions and stop in a resumable blocked state. |
| Retry | Apply bounded, diagnostic-code-based retry policy. |
| Evidence | Project verified artifacts and diagnostics through Foundation types. |
| Reproducibility | Persist request, stage results, events, and artifact references through `FlowRunLedgerPersisting`. |
| Agent operation | Keep typed CLI/API state and structured diagnostics. |
| Human review | Preserve approval, diff, artifact, and failure evidence. |
| Foundation-first storage | Persist, load, and verify canonical `ArtifactReference` values through `FlowArtifactPersisting`; reject non-canonical artifact records at the storage boundary. |

## Foundation contract

`CircuiteFoundation` is the only source for shared engine, artifact,
provenance, evidence, diagnostic, and design-object contracts. This package
does not select a project filesystem. Concrete `.xcircuite` storage is supplied
by Xcircuite through `FlowRunLedgerPersisting`; new cross-package APIs use
Foundation types at the boundary.

## Acceptance criteria

- `swift build` succeeds with a local `CircuiteFoundation` dependency.
- Existing DesignFlowKernel tests continue to compile and run.
- `DefaultFlowEngine` conforms to `Engine` without duplicating orchestration.
- Evidence conversion never guesses a digest or byte count.
- README and design documents describe the ownership boundary for implementers.

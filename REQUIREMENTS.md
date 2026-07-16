# DesignFlowKernel requirements

## Required capabilities

| Capability | Requirement |
|---|---|
| Engine boundary | Expose flow execution through `CircuiteFoundation.Engine`. |
| Stage execution | Accept independently implemented `FlowStageExecutor` values. |
| Trust gates | Evaluate tool qualification before a stage executes. |
| Approval | Persist approval decisions and stop in a resumable blocked state. |
| Retry | Apply bounded, diagnostic-code-based retry policy. |
| Evidence | Return verified artifacts, provenance, and diagnostics directly through Foundation protocols. |
| Reproducibility | Persist request, stage results, events, and artifact references through `FlowRunLedgerPersisting`. |
| Agent operation | Keep typed CLI/API state and structured diagnostics. |
| Human review | Preserve approval, diff, artifact, and failure evidence. |
| Foundation-first storage | Persist, load, and verify canonical `ArtifactReference` values through `FlowArtifactPersisting`; reject non-canonical artifact records at the storage boundary. |

## Foundation contract

`CircuiteFoundation` is the only source for shared engine, artifact,
provenance, evidence, diagnostic, and design-object contracts. This package
does not select a project filesystem. A composing application binds a validated
`FlowWorkspaceID` to concrete storage supplied through
`FlowRunLedgerPersisting`; cross-package APIs use Foundation types directly.

## Acceptance criteria

- `swift build` succeeds with a local `CircuiteFoundation` dependency.
- Existing DesignFlowKernel tests continue to compile and run.
- `DefaultFlowEngine` conforms to `Engine` without duplicating orchestration.
- `FlowRunResult` evidence must exactly match its stage artifacts and diagnostics.
- README and design documents describe the ownership boundary for implementers.

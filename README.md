# DesignFlowKernel

Shared flow kernel for the semiconductor design harness. Humans (circuit-studio),
agents, and CI run the same flow through this kernel so that tool selection, trust
gates, stage results, and artifacts have one meaning. The kernel owns ordering,
gating, persistence, and resume — it contains no SPICE/DRC/LVS/PEX domain logic
(that stays in the engine packages, connected via the `Xcircuite` runtime).

## Types

| Type | Responsibility |
|---|---|
| `FlowOperationRequest` | Project root, run ID, intent, stage sequence |
| `FlowStageDefinition` | Stage ID, display name, tool trust requirement, `requiresApproval` |
| `FlowStageExecutor` | Protocol: delegates domain-specific stage execution to engine adapters |
| `DefaultFlowOrchestrator` | Creates `.xcircuite/runs/<run-id>/`, applies tool trust gates, executes stages, applies the approval gate, persists results |
| `FlowStageResult` / `FlowStageStatus` | Typed stage outcome: status, diagnostics, gate results, artifact references |
| `FlowGateResult` / `FlowGateStatus` | Pass/fail/waived/incomplete per gate |
| `FlowRunResult` / `FlowRunStatus` | Run status, run directory, stage results |
| `FlowDiagnostic` / `FlowDiagnosticSeverity` | Structured diagnostics (never opaque strings) |
| `FlowExecutionContext` / `FlowExecutionError` | Execution environment and typed failures |

## Approval gate and resume

Stages with `requiresApproval` evaluate an `approval` gate after execution, read from
`runs/<run-id>/approvals/<stage-id>.json` (`XcircuiteApprovalRecord`, latest wins):

| Approval state | Gate result | Run behavior |
|---|---|---|
| approved | passed | continue to the next stage |
| rejected | failed (`STAGE_REJECTED`) | stage fails, run fails |
| absent | — | run stops as `blocked` (`APPROVAL_PENDING`) |

Resume is re-running the same runID: `approvals/` survives run directory re-creation,
so recording a decision and re-running moves past the gate. The review cockpit and
the agent both operate on this one ledger — block → decide → resume.

## Dependencies

`XcircuitePackage` (artifact contract), `ToolQualification` (trust gates).

## Build & test

```bash
swift build
swift test
```

# DesignFlowKernel Remaining Tasks

Updated: 2026-08-11

## Remaining tasks

The kernel now owns content-addressed candidate-stage attestations, exact
candidate evidence bindings, promotion decisions, and bounded promotion
authorizations. It also owns generic immutable per-stage input scoping: run-plan
schema version 2 persists the bindings, request validation rejects undeclared,
duplicate, or empty input sets, and each executor receives only its target stage's
bindings. Every concrete executor invocation receives a distinct typed attempt ID so
attempt-local evidence cannot be reused by a later retry. `DefaultFlowCandidatePromotionAuthorizer` re-reads persisted
evidence and approval artifacts through an injected reader, verifies byte count,
content digest, decoded value, human-review policy, exact evidence binding, and
the exact retained base-to-candidate design-diff binding. The promotion decision
digest includes the diff content identity, and authorization validation rejects a
request that substitutes another diff. It emits policy authorization without
performing reference CAS.

No additional package-owned P0 implementation task is currently identified for
this contract. Behavioral execution of the newly added stage-input and authorizer tests and the
composed Xcircuite promotion path still has to be retained before this scope can
be reported as behaviorally verified.

## External prerequisites

Concrete `.xcircuite` artifact persistence, FlowRuntime engine composition,
stage-attestation production, grant validation, reference CAS, and promotion
ledger recording belong to Xcircuite. UI review belongs to circuit-studio.
Domain verdicts remain in their domain engines.

## Evidence reviewed

- `GOAL_STATUS.md`
- `README.md`
- `DESIGN.md`
- `REQUIREMENTS.md`
- `Sources` incomplete-implementation marker scan

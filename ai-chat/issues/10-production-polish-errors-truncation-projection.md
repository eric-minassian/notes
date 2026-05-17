# 10 — Production polish: error handling, truncation, projection

**Type**: AFK
**Label**: ready-for-agent

## What to build

The robustness pass on the Proposal Executor and Browser Turn Orchestrator
that takes them from "happy path works" to "v1-shippable." All behaviors
are already named in the PRD's runtime defaults; this slice implements and
tests them.

- **Error normalization** in the Proposal Executor:
  - 4xx from API → `{ status: "error", error: { kind: "client", … } }` fed
    back into the next turn. Model sees it and may propose differently.
  - 5xx from API → `{ status: "error", error: { kind: "server", … } }`,
    same feedback path.
  - Network / timeout → surfaced in the chat UI as "the call didn't
    complete," with a "try again" affordance that re-submits the same
    proposal for approval (no silent retry).
- **No auto-retry**: the agent gets one shot per proposal. Retries always
  require a new approval cycle.
- **Response truncation**: 4KB default cap on tool-result body fed back to
  the model, with a `…truncated, N more bytes` note appended.
- **Per-tool projection**: when the [[Tool Manifest]] declares a
  `responseProjection`, the executor applies it before truncation so the
  important fields survive even when the raw response is large.
- **Decline-then-continue UX**: on decline, the model receives a
  structured `{ status: "declined", reason?: "user did not approve" }`
  result and is prompted by the system rules to acknowledge the decline
  and either suggest an alternative or stop — not silently retry.

Tests: Proposal Executor — exhaustive table-driven tests on the error
normalization, truncation, and projection paths. Browser Turn Orchestrator
— reducer tests for the decline-then-continue and network-error flows.

## Acceptance criteria

- [ ] A 4xx from the API does not crash the conversation; the model
      receives the error and produces a reasonable next turn.
- [ ] A 5xx from the API behaves the same; no auto-retry happens.
- [ ] A response larger than 4KB is truncated, the model receives the
      truncation note, and the conversation continues.
- [ ] A tool with a configured `responseProjection` receives the projected
      shape, not the raw response.
- [ ] Declining a proposal leads to a coherent next assistant turn
      (acknowledge + suggest / stop), not a silent retry of the same
      proposal.
- [ ] Network errors surface in the chat UI with a manual retry
      affordance.

## Blocked by

- 05-first-end-to-end-tool-call

# 08 — Risk classes + approval card hardening for write/destructive

**Type**: HITL
**Label**: ready-for-agent

## What to build

Promote the Approval Card UI from "minimal v1" to the production version
that handles write and destructive operations safely. Plumb risk classes
end-to-end so the UI can render them.

- Manifest already carries `riskClass` (read / write / destructive);
  surface it in the proposal payload to the browser.
- Approval Card UI variants:
  - **read**: current minimal card.
  - **write**: prominent tool description, all args visible (no
    collapse), risk-class badge, approve / decline.
  - **destructive**: write-card styling plus a confirmation gate (e.g.,
    type-to-confirm the operation name, or a two-step "are you sure"
    pattern — final design is the HITL part of this slice).
- All cards highlight `id`-shaped arguments visually (per CONTEXT and
  ADR 0001 — IDs are the attack surface for an injected proposal).
- Add at least one write-class endpoint to the allowlist to exercise the
  flow end-to-end.

**HITL**: the visual design and copy of the write/destructive cards —
specifically the destructive confirmation gate — should be reviewed by a
designer (or whoever owns frontend UX) before merge. The functional
behavior is mechanical; the gate's specific UX is a real design call.

Tests: Approval Card UI snapshot / interaction tests for each risk-class
variant. Proposal Executor: no logic change in this slice, but add a test
that a write-class proposal still flows through cleanly.

## Acceptance criteria

- [ ] A read proposal renders the read variant.
- [ ] A write proposal renders the write variant with all args visible,
      no collapse, and an obvious risk-class indicator.
- [ ] A destructive proposal renders the write variant plus a confirmation
      gate; approving without satisfying the gate is impossible.
- [ ] In all variants, any argument whose name matches the project's
      ID-shaped conventions is visually distinguished.
- [ ] At least one write-class tool can be invoked end-to-end via this
      flow and the call succeeds against the real API.
- [ ] Designer / UX owner has reviewed the destructive-gate design.

## Blocked by

- 06-smithy-to-manifest-generator

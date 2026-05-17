# 0001 — The agent is a UI, not a trust boundary

## Status

Accepted.

## Context

We are adding an AI chat/agent to a React SPA backed by AWS APIs (Cognito for
auth). The agent can propose backend API calls; the user approves each one;
the browser executes the approved call using the user's existing access token.
The LLM never sees the token.

A natural question: should the chat backend independently re-validate every
proposed call against the user's permissions before sending it to the
browser? Should the allowlist enforce per-call authorization server-side?
Should we treat the agent's outputs with a privilege model distinct from the
user's own?

## Decision

No. The agent is treated as **a different UI on top of the same APIs**, not
as a privileged actor. The backend APIs remain the sole authorization
boundary, exactly as they are for the existing SPA. The user's access token,
issued by Cognito, is the user's identity for every call regardless of
whether the call originated from a click or from an agent-emitted
[[Tool-Call Proposal]] the user approved.

Concretely: anything the user can already do via the existing UI, the agent
can propose. Anything the user can't do via the existing UI, the API will
reject — and that rejection is the only authorization check we rely on.

## Consequences

- **The agent adds no new backdoors.** It cannot do anything the user
  couldn't already do by clicking. Per-call HITL approval is defense in
  depth against the user being *tricked* into approving something they could
  legitimately do but shouldn't (e.g., prompt-injected tool results), not
  against privilege escalation.
- **No server-side re-validation of proposals.** The chat backend forwards
  what the model emitted; the browser asks the user; the API enforces.
- **API authorization quality is load-bearing.** If an endpoint trusts an
  ID in the request body without re-deriving ownership from the token, that
  is a pre-existing IDOR — but the agent makes it dramatically easier to
  exploit because the LLM can be coaxed into substituting IDs the user
  wouldn't think to type. We assume backend APIs are doing authn/authz
  correctly today, and treat any failure of that assumption as a backend
  bug, not an agent bug.
- **Allowlist scope is a UX decision, not a security one.** We may still
  curate which operations are exposed (to keep the model focused, reduce
  catalog size, suppress nonsensical-in-chat operations), but the curation
  is not protecting the backend. Removing something from the allowlist
  means the agent won't propose it, not that the user couldn't still
  perform it through the regular UI.
- **Token scope and overprovisioned permissions matter more, not less.** If
  the user's token grants ability to call admin endpoints that the existing
  UI hides, the agent will happily find and surface those endpoints. Token
  scopes should reflect what the user *should* be able to do, not what
  any user can do.

## Alternatives considered

- **Server-side re-validation of every proposal against a user
  permissions store.** Rejected: duplicates the API's own authorization
  checks (which is the canonical source of truth) and can drift from
  them, producing a *worse* security posture than relying on the API.
- **A separate, narrower set of "agent-allowed" actions distinct from
  what the user can do in the UI.** Rejected: complicates the mental
  model, requires a parallel permissions system, and breaks the
  "the agent is just a different UI" framing.

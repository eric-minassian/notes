# 05 — First end-to-end tool call (one read endpoint, hand-crafted manifest)

**Type**: AFK
**Label**: ready-for-agent

## What to build

The first end-to-end [[Tool-Call Proposal]] flow: the agent proposes one
backend API call, the user approves it, the browser executes the call with
its access token, the result feeds back into the model. This validates the
entire suspend-resume-via-browser pattern that ADR 0001 hinges on.

Pick one simple, low-risk read endpoint (suggested: a `getCurrentUser` or
equivalent that requires only the caller's identity, no extra args).

- [[Tool Manifest]] (hand-written for this slice): a JSON file with one
  entry — name, description, risk class (`read`), arg schema, response
  projection rule (or default 4KB truncate).
- Tool Manifest Validator (server-side): validates that any tool-use block
  the model emits references an allowlist entry and the args match the
  schema. Rejects malformed proposals before sending to browser.
- Tool Registry (Browser): one entry mapping the tool name to the existing
  frontend SDK call. The registry is the only place the SDK is invoked —
  we do not build a parallel HTTP client.
- Proposal Executor (Browser): validates args against the manifest,
  dispatches via the registry, applies response projection / truncation,
  normalizes successes / errors / declines into `{ id, status, body?, error? }`.
- Browser Turn Orchestrator: state machine handles the cycle — receive
  proposals → render approval cards → collect approve/decline decisions →
  invoke Proposal Executor for approved → assemble tool-results → send
  next turn.
- Approval Card UI (minimal v1): renders tool name, description, formatted
  args, approve / decline buttons. Risk-class styling deferred to issue 08.
- Chat service Agent Loop: passes the manifest's tool definitions to
  Bedrock; on receiving a turn with `toolResults`, feeds them back into
  the next Bedrock call.

Tests: Tool Manifest Validator (table-driven on valid/invalid proposals),
Proposal Executor (with mocked SDK), Browser Turn Orchestrator reducer
(approve / decline / error flows), Agent Loop (turn with tool-use, turn
with tool-result feedback).

## Acceptance criteria

- [ ] "Who am I?" causes the agent to propose the read tool; an approval
      card renders showing the tool name and args.
- [ ] Approving fires the SDK call; the response is fed back into the model
      and the agent's final reply uses the data.
- [ ] Declining records a decline; the agent acknowledges and stops or
      suggests an alternative.
- [ ] Args that fail manifest validation server-side never reach the
      browser; the chat service logs the rejection and the agent reroutes.
- [ ] The browser-side dispatch goes through the existing frontend SDK
      (auth headers, base URL, retry, tracing all inherited).
- [ ] The access token is never sent to the chat service; the chat service
      never has it in scope.
- [ ] Truncation kicks in if the response exceeds 4KB; the model receives
      a `…truncated` note.

## Blocked by

- 02-bedrock-text-conversation-streaming

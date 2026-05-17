# Context

AI chat/agent embedded in an existing React SPA. The agent can answer questions,
direct users around the site, and propose API calls against our backend on the
user's behalf. The user manually approves every proposed call. The LLM never
sees the user's access token.

## Glossary

### Tool Schema
The mechanically-derivable definition of a single backend operation exposed to
the agent: name, input shape, output shape. Generated from our Smithy models
(via Smithy → OpenAPI or directly from Smithy shapes). Not the same as a
[[Tool Description]].

### Tool Description
The natural-language hint that tells the LLM *when* to pick a given
[[Tool Schema]]. Human-authored, tuned for the model, distinct from the
SDK-facing documentation in Smithy `@documentation` traits.

### Allowlist
The curated subset of backend operations the agent is permitted to invoke. Not
every operation in the Smithy model is exposed. Each entry pairs a
[[Tool Schema]] with a [[Tool Description]] and a risk classification (read /
write / destructive — to be refined). Defaults to deny.

### Runbook Pipeline
Runbooks are versioned in this repo (`/runbooks/*.md`), reviewed via PR,
and synced to the S3 prefix backing the Bedrock Knowledge Base on merge
to main, which triggers a KB ingestion job. No live-edit / hot-reload
path in v1. Eval suite for retrieval quality deferred.

### Agent Scope
What the agent is *for*. In v1: (a) procedurally helping users accomplish
goals on the site by emitting [[Tool-Call Proposal|proposals]] guided by
[[Runbook|runbooks]]; (b) navigating users to specific pages via
[[Navigation Intent|navigation intents]]; (c) answering questions about the
user's own data via read [[Tool-Call Proposal|proposals]] (subject to
per-call approval). **Out of scope in v1**: answering questions about
product policy, pricing, plans, legal, or any other declarative content
where a hallucinated answer would be a liability. For those, the agent
declines to answer directly and emits a [[Navigation Intent]] to the
relevant page (pricing, docs, contact-us) with a one-line handoff.

### Runbook
An AI-curated, short-form procedural document describing how to accomplish a
multi-step goal by chaining [[Tool Schema|tool calls]] (e.g. "to cancel a
subscription: getSubscription → requestCancellation → poll
getCancellationStatus"). Distinct from the ops team's operational runbooks,
which are written for humans and too verbose to feed to the model. Stored in a
Bedrock Knowledge Base; the agent retrieves them on demand via an explicit
lookup tool, not via automatic retrieval.

### Navigation Intent
A tool-like instruction emitted by the agent telling the browser to navigate
the user to a specific URL within the app (e.g. `/billing/invoices`).
Auto-executed without per-call approval; the browser shows a "Taking you
to …" toast for transparency. Distinct from a [[Tool-Call Proposal]] — no
access token is used, no backend state changes. Out of scope in v1: non-URL
client actions (opening drawers, scrolling to sections, prefilling forms).

### Tool Manifest
The single source of truth for the agent's catalog: a build-time-generated
JSON file derived from Smithy that, for each [[Allowlist]] entry, declares
the tool name, argument schema, response-projection rule, risk class, and
[[Tool Description]]. Used by the chat service to validate
[[Tool-Call Proposal|proposals]] before forwarding to the browser, and by
the browser to validate proposal arguments before executing them. Pure
data — does not itself execute calls.

### Tool Registry (Browser)
A small runtime table in the SPA that maps each tool name in the
[[Tool Manifest]] to a function that calls the existing frontend SDK
(e.g. `"getInvoice" -> (args) => sdk.invoices.get(args)`). Hand-written
or codemod-generated. The registry exists so the agent's execution path
inherits everything the SDK already does (base URL resolution, access-token
attachment, token refresh, retry, tracing, error normalization) — we do
not build a parallel HTTP client for agent-initiated calls.

### Tool-Call Proposal
A structured object emitted by the agent describing a single API call it wants
to make: which [[Allowlist]] entry, with which arguments. The proposal is sent
to the browser, which shows it to the user for approval and — if approved —
executes the call with the access token. The LLM only ever sees the proposal
and the response payload, never the token.

### Chat Service
The new backend service we are adding to host the agent loop. It is a stateless
service that receives a turn (user message + prior transcript + any tool
results from the previous round), calls Bedrock, and returns the next
assistant turn (text + [[Tool-Call Proposal|proposals]] + [[Navigation Intent|navigation intents]]).
It sits behind our existing router service, which handles route-based authn/authz;
the [[Chat Service]] itself does not implement Cognito wiring. Known-deferred
in v1: per-user rate limits and per-user Bedrock cost budgets (the
team has accepted the abuse/cost risk for v1).

### Chat Session
A single ongoing conversation between the user and the agent. The transcript
(user messages, assistant turns, [[Tool-Call Proposal|proposals]], tool results,
declines) lives in the browser in v1; the chat backend is stateless and
replays the transcript to the model on each turn. Cross-device persistence is
deferred to p1/p2. Server-side audit logging of each model
request/response is still in scope via CloudWatch.

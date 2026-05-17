# PRD: AI Chat Agent for the SPA

## Problem Statement

Users of our React SPA accomplish goals by navigating to the right page,
finding the right control, and clicking through the right sequence of forms.
For non-trivial flows (cancelling a subscription, updating billing, looking
up their own usage) this means knowing the site's information architecture
or contacting support. Power users want a faster path; new users get lost.
The site's API surface is rich (50–100 endpoints) but discoverable only
through the UI.

## Solution

A chat panel embedded in the SPA where users can ask questions, be directed
to the right page, and instruct an AI agent to perform actions on their
behalf via our existing APIs. The agent proposes each API call as a
[[Tool-Call Proposal]]; the user approves each one before it fires; the
browser executes the call with the user's existing access token. The LLM
never sees the token. The agent is a UI on top of the existing APIs — not
a new trust boundary (see [ADR 0001](./docs/adr/0001-agent-is-a-ui-not-a-trust-boundary.md)).

## User Stories

1. As a logged-in user, I want to open a chat panel inside the SPA, so that I can ask the agent for help without leaving my current page.
2. As a logged-in user, I want to ask "how do I do X?" and receive a step-by-step answer, so that I don't have to dig through documentation.
3. As a logged-in user, I want to ask "take me to my billing page" and have the agent navigate me there, so that I don't have to learn the site's information architecture.
4. As a logged-in user, I want to ask "what's my current plan?" and have the agent answer using my real account data, so that I don't have to navigate to a settings page to check.
5. As a logged-in user, I want the agent to walk me through a multi-step task (e.g., "cancel my subscription") by chaining the required API calls, so that I don't have to perform each step manually.
6. As a logged-in user, I want to see exactly which API call the agent wants to make, with all arguments visible, before it executes, so that I retain control over actions taken on my account.
7. As a logged-in user, I want to approve or decline each proposed API call individually, so that no action is taken without my explicit consent.
8. As a logged-in user, I want to see the risk classification of each proposed call (read / write / destructive), so that I can give appropriate scrutiny to high-impact actions.
9. As a logged-in user, I want IDs and identifier-shaped arguments to be visually prominent in approval cards, so that I can catch mis-targeted calls (e.g., the wrong invoice ID).
10. As a logged-in user, I want the agent's text response to stream into the chat as it's generated, so that the experience feels responsive.
11. As a logged-in user, I want a brief toast when the agent navigates me to a new page, so that the navigation isn't surprising and I can undo it.
12. As a logged-in user, I want the agent to decline to answer questions about policy / pricing / plans and instead navigate me to the relevant page (or contact-us), so that I don't get a hallucinated answer to a high-stakes question.
13. As a logged-in user, I want the agent's session to persist within a single browser tab so I can have a multi-turn conversation, but not across tabs or devices in v1.
14. As a logged-in user, I want the agent to handle API errors gracefully — telling me the call failed and what it would do next — rather than silently retrying or claiming success.
15. As a logged-in user, when I decline a proposed call, I want the agent to acknowledge the decline and either suggest an alternative or stop, so that declines aren't dead ends.
16. As an engineer adding a new endpoint to the API, I want a documented path to add that endpoint to the agent's [[Allowlist]] with a description and risk classification, so that the agent stays in sync with the API.
17. As an engineer, I want the [[Tool Manifest]] to be generated mechanically from our Smithy models, so that schemas can't drift from the source of truth.
18. As an engineer, I want a curated allowlist layer over the auto-generated catalog, so that not every endpoint is exposed to the agent by default.
19. As an engineer authoring a [[Runbook]], I want runbooks to live in the repo as Markdown files, reviewed via PR, so that AI-facing content goes through the same review process as code.
20. As an engineer, I want the runbook sync to happen automatically on merge to main, so that no manual KB-management step is required.
21. As an engineer, I want every API call the agent makes to flow through the existing frontend SDK (via the [[Tool Registry (Browser)]]), so that auth-header attachment, base-URL resolution, retry, and tracing aren't reimplemented.
22. As an engineer debugging an agent turn, I want structured logs in CloudWatch containing the model input shape, output shape, proposals emitted, and token counts (but not message plaintext or tool-result payloads), so that I can diagnose issues without creating PII liability.
23. As an SRE, I want the [[Chat Service]] to be stateless behind our existing router service, so that it inherits route-based authn/authz and scales as a normal Lambda.
24. As a security reviewer, I want the architecture to make clear that the LLM is never in the authorization trust path and that the backend API's existing authz checks are the security boundary (see ADR 0001), so that the agent doesn't introduce a backdoor.
25. As a security reviewer, I want the access token to live exclusively in the browser and never be transmitted to the chat service or to Bedrock, so that the LLM-controlled surface cannot exfiltrate credentials.

## Implementation Decisions

### Modules

**Backend — Chat Service**

- **Agent Loop** *(deep)*: Orchestrates Bedrock Converse calls. Receives the
  full transcript (browser-held, replayed each turn), calls Bedrock with the
  composed system prompt and tool definitions, parses the model response,
  emits either streamed text + zero-or-more [[Tool-Call Proposal|proposals]]
  + zero-or-more [[Navigation Intent|navigation intents]], or — when given
  tool results in the request — feeds them back to the model and continues
  the loop. Returns to the browser when the model emits no further
  proposals.
- **Tool Manifest Validator** *(deep, pure function)*: Validates that any
  tool-use block produced by the model references an [[Allowlist]] entry
  and that its arguments conform to the schema declared in the
  [[Tool Manifest]]. Rejects malformed proposals before they reach the
  browser. This is sanity-checking, not authorization (per ADR 0001).
- **System Prompt Builder** *(deep, pure function)*: Composes the system
  prompt from (a) static agent-role text, (b) the navigation-vs-API
  taxonomy and the "decline policy/pricing questions, navigate instead"
  rule, (c) the always-on [[Runbook]] title index (one line per runbook),
  (d) per-turn user identity context (name, tier — nothing sensitive).
- **Runbook Retriever** *(shallow)*: Wraps Bedrock Knowledge Base `Retrieve`
  for the agent's `lookupRunbook` tool implementation.
- **Bedrock Client Wrapper** *(shallow)*: Thin Converse/ConverseStream
  wrapper with error normalization.
- **Conversation Turn Handler** *(shallow)*: Lambda entry point. Decodes
  request, invokes Agent Loop, streams response back via Lambda response
  streaming.

**Build pipeline**

- **Smithy → Manifest Generator** *(deep, deterministic)*: Build-time tool
  consuming the Smithy model, the allowlist file, and the description
  overrides; emits the [[Tool Manifest]] JSON consumed by both the chat
  service and the SPA. Validates that every allowlisted name exists in the
  Smithy model and that descriptions and risk classes are present for each
  entry.

**Frontend — SPA**

- **Browser Turn Orchestrator** *(deep, state machine)*: Drives the cycle:
  send turn → render streamed reply → render approval cards for proposals →
  collect user approval / decline decisions → invoke Proposal Executor for
  each approved proposal → assemble tool-results array → send next turn.
  Holds the transcript in memory (browser-held, per ADR-aligned decision).
  Testable as a reducer.
- **Proposal Executor** *(deep)*: Given a [[Tool-Call Proposal]], validates
  its args against the [[Tool Manifest]], looks up the matching entry in
  the [[Tool Registry (Browser)]], invokes the SDK, applies the per-tool
  response projection rule (or 4KB default truncation), normalizes
  successes / errors / declines into the tool-result shape the next turn
  expects.
- **Tool Registry (Browser)** *(shallow, data)*: Static map from tool name
  to a function that calls the existing frontend SDK. Hand-written or
  codemod-generated. Exists so the agent's call path inherits everything
  the SDK already does.
- **Approval Card UI** *(shallow)*: Per-proposal component. Renders tool
  name, description, risk class, and arguments with `id`-shaped values
  visually prominent. Approve / decline buttons.
- **Chat UI** *(shallow)*: Message list, streaming text renderer, input
  box, interleaved approval cards and navigation toasts.
- **Navigation Intent Handler** *(shallow)*: Auto-executes [[Navigation Intent]]
  emissions: SPA router push + transient "Taking you to …" toast with
  undo affordance.

**Infrastructure**

- **CDK app** *(shallow, declarative)*: Lambda Function URL with response
  streaming, fronted by CloudFront; IAM allowing the Lambda to call
  Bedrock Converse, Bedrock Knowledge Base Retrieve, and emit CloudWatch
  Logs; S3 bucket holding the runbook source for the Knowledge Base;
  the Bedrock Knowledge Base resource itself.
- **Runbook sync CI step** *(shallow)*: On merge to main, uploads
  `/runbooks/*.md` to S3 and triggers a Bedrock KB ingestion job.

### Interfaces (decision-level, not code)

- **Browser ⇄ Chat Service**: A single endpoint accepting
  `{ transcript, userMessage?, toolResults? }` and streaming back
  `{ assistantText, proposals[], navigationIntents[] }`. Transcript is the
  full conversation array (Bedrock Converse message shape, including
  prior tool-use and tool-result blocks). Service is stateless; sits
  behind the existing router service which enforces Cognito identity.
- **[[Tool-Call Proposal]] shape**: `{ id, tool, args, riskClass }` where
  `riskClass ∈ {read, write, destructive}`. The browser returns
  `{ id, status: "ok" | "error" | "declined", body?, error? }` and threads
  these into the next turn's `toolResults`.
- **[[Navigation Intent]] shape**: `{ url }`. URL only; no drawer-opening,
  scrolling, or form-prefill in v1.
- **[[Tool Manifest]] schema**: Per entry — `name`, `description`,
  `riskClass`, `argSchema` (JSON Schema), `responseProjection?` (path
  selectors), `maxResponseBytes?` (default 4096).
- **Runbook frontmatter schema**: `name`, `title`, `tools-referenced`,
  `tags`, `last-reviewed`. CI validates that every `tools-referenced`
  entry exists in the allowlist.

### Architectural decisions

- LLM never sees the access token. Browser executes all API calls. See
  ADR 0001.
- Backend API authorization is the only authorization checkpoint.
  Per-call human-in-the-loop approval is defense in depth against social
  engineering of the user, not against privilege escalation.
- Conversation transcript is browser-held in v1. Server is stateless.
  Cross-device persistence and cross-tab sync are deferred.
- Runbooks (procedural knowledge) live in a Bedrock Knowledge Base and
  are retrieved on demand via an explicit `lookupRunbook` tool — not via
  automatic retrieval — so the model's retrievals are deliberate and
  debuggable.
- Product/policy/pricing Q&A is explicitly out of scope. The agent
  declines and emits a [[Navigation Intent]] (typically pricing, docs,
  or contact-us) with a one-line handoff.
- Navigation intents auto-execute without per-call approval. API calls
  (read or write) always require per-call approval in v1.
- The agent does not run macro-tools or batch approvals in v1. It chains
  primitive tools; the user approves each one.

### Model and runtime defaults

- **Model**: Claude Haiku 4.5 on Bedrock. Escalate to Sonnet 4.6 (and
  then Opus 4.7) if quality is insufficient in practice.
- **Streaming**: Lambda response streaming over Function URL, fronted by
  CloudFront. Tool-call proposals are emitted whole after the streamed
  text; no partial-proposal streaming.
- **Context window**: no transcript truncation or summarization in v1.
  Token counts are logged; revisit when real conversations exceed ~50K
  tokens.
- **Auto-retry on tool errors**: none. The model sees the error and may
  propose a different action; the user must re-approve to retry.
- **Response payload handling**: per-tool projection if declared in the
  manifest, else truncate at 4KB with a "…truncated" note.

## Testing Decisions

A good test in this codebase exercises observable external behavior of a
module — given inputs, the right outputs / side effects — without
asserting on internal structure. We avoid mocking the things we're
testing (manifest validator, prompt builder, executor logic are all
pure); we do mock the Bedrock and SDK boundaries.

Modules with dedicated test suites in v1 (all deep modules):

- **Agent Loop** — fixture-driven tests with a mocked Bedrock client.
  Given a transcript and a scripted model response (text-only,
  text+proposals, multi-proposal, tool-result feedback), assert the
  resulting `{ assistantText, proposals, navigationIntents }` shape and
  the sequence of Bedrock calls.
- **Tool Manifest Validator** — table-driven tests covering valid
  proposals, unknown tool names, missing required args, type mismatches,
  extra args, and arg coercion edge cases.
- **System Prompt Builder** — snapshot-style tests asserting prompt
  composition for representative inputs (different runbook indexes,
  different user identity contexts). Plus invariants: never embeds raw
  user message content, always includes the navigation/scope rules.
- **Smithy → Manifest Generator** — fixture-driven: given a small Smithy
  model and an allowlist, assert the emitted manifest. Cover the
  validation paths (allowlisted-but-missing, missing description,
  missing risk class).
- **Browser Turn Orchestrator** — reducer-style tests over the state
  machine: dispatching `userTyped`, `streamedTokenReceived`,
  `proposalsReceived`, `proposalApproved`, `proposalDeclined`,
  `toolResultReceived`, `turnComplete`. Cover error states, multi-proposal
  turns, and decline-then-continue flows.
- **Proposal Executor** — given a proposal and a mocked SDK, assert that
  args are validated, the right SDK method is invoked, the response is
  projected/truncated per manifest rules, and errors are normalized.

Modules **not** getting dedicated tests in v1: Conversation Turn Handler
(covered transitively by Agent Loop tests + manual smoke), Bedrock
Client Wrapper (thin), Runbook Retriever (thin), Tool Registry (data),
Approval Card UI, Chat UI, Navigation Intent Handler, CDK app.

No model-evaluation suite in v1.

No Playwright end-to-end in v1.

Prior art: this is a new codebase — no prior tests to mirror.

## Out of Scope

Explicitly deferred in v1:

- Cross-device / cross-tab conversation persistence (transcript is
  browser-tab-local in v1).
- Per-user rate limiting and per-user Bedrock cost budgets. The team has
  accepted the abuse and cost risk for v1.
- "Auto-approve reads" or any per-session approval-batching UX. Every
  API call gets its own approval card.
- Macro-tools that bundle several underlying calls behind one approval.
- Server-side re-validation of proposals against user permissions. See
  ADR 0001 — backend API authz is the only check.
- Product / policy / pricing / legal Q&A. The agent declines and
  navigates.
- Non-URL navigation intents: opening drawers, scrolling to sections,
  prefilling forms.
- Model-evaluation suite for retrieval / agent quality.
- A Knowledge Base for product documentation (separate from
  [[Runbook|runbooks]]).
- Internationalization of agent responses.
- Multi-tenant runbook isolation (one-tenant-per-deployment assumed in
  v1).
- Anonymous / pre-login chat.
- Transcript content (user messages, tool-result payloads) in logs.
  We log shape and token counts only.
- Compliance-driven log retention design (SOC2 / GDPR / HIPAA).
- Live / hot-reload runbook authoring. Sync is CI-on-merge only.
- Mixed-model strategies (using Sonnet for hard turns and Haiku for
  easy ones). Single model in v1.

## Further Notes

- The split between the [[Tool Manifest]] (data) and the
  [[Tool Registry (Browser)]] (runtime function table) is the
  load-bearing decision that lets us use the existing frontend SDK
  without rebuilding HTTP plumbing. Preserve this split as the codebase
  evolves.
- The [[Runbook]] index in the system prompt should stay short (titles +
  one-line summaries). The full runbook bodies come in via
  `lookupRunbook` retrievals. This keeps token cost down and makes the
  agent's retrievals visible in logs.
- The "agent is a UI, not a trust boundary" framing (ADR 0001) is the
  single most load-bearing decision. Anything that introduces
  server-side privilege checks distinct from the backend API's checks
  is breaking ADR 0001 and should be revisited.
- The known-deferred items in [Out of Scope](#out-of-scope) are
  deliberate v1 trade-offs, not oversights. Specifically, per-user rate
  limits and cost budgets are the highest-risk deferral — if v1 reaches
  any non-trivial user count, prioritize these before broader rollout.

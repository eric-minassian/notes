# Design: AI Chat Agent for the SPA

Companion to [PRD.md](./PRD.md), [CONTEXT.md](./CONTEXT.md), and
[ADR 0001](./docs/adr/0001-agent-is-a-ui-not-a-trust-boundary.md). The PRD
covers *what* we are building and *why*. This document covers *how*.

Domain terms (`[[Term]]`) are defined in CONTEXT.md.

---

## 1. Goals & non-goals

**Goals**

- Let users accomplish goals in the SPA by chatting with an AI agent that
  can navigate the site and propose backend API calls on their behalf.
- Preserve the existing security model: the user's access token never
  leaves the browser; the LLM is never in the authorization trust path.
- Make the agent maintainable: the catalog of API operations comes from
  Smithy (no schema drift), and procedural knowledge ([[Runbook|runbooks]])
  is reviewed via PR.

**Non-goals (v1)** — see PRD §"Out of Scope" for the full list. Key
omissions: cross-device transcript persistence, per-user rate limits and
cost budgets, product/policy Q&A, macro-tools, model-evaluation suite.

---

## 2. System architecture

```mermaid
flowchart LR
    User([User])
    SPA[React SPA<br/>· Chat UI<br/>· Browser Turn Orchestrator<br/>· Proposal Executor<br/>· Tool Registry<br/>· Navigation Intent Handler]
    Router[Router Service<br/>route-based authn/authz]
    Chat[Chat Service Lambda<br/>· Agent Loop<br/>· System Prompt Builder<br/>· Tool Manifest Validator<br/>· Runbook Retriever]
    BackendAPI[Existing Backend APIs<br/>Cognito-authorized]
    Bedrock[Bedrock Converse<br/>Claude Haiku 4.5]
    KB[Bedrock Knowledge Base<br/>Runbooks]
    S3[(S3 — runbook source)]
    CW[CloudWatch<br/>logs · metrics · X-Ray]

    User <-->|chat panel| SPA
    SPA -->|access token| BackendAPI
    SPA -->|"/chat/turn (Cognito auth)<br/>{transcript, userMessage?, toolResults?}"| Router
    Router --> Chat
    Chat -->|ConverseStream| Bedrock
    Chat -->|Retrieve| KB
    Chat -.->|"structured logs<br/>shape only, no plaintext"| CW
    S3 -.->|ingestion job| KB

    classDef external fill:#eee,stroke:#999;
    class User,Bedrock,KB,S3,CW,BackendAPI,Router external;
```

**The flow of authority**: the user's access token lives only in the SPA
and is attached only to direct calls to the existing Backend APIs. The
chat service never sees it. The LLM never sees it. See [ADR 0001](./docs/adr/0001-agent-is-a-ui-not-a-trust-boundary.md).

---

## 3. Components

### 3.1 SPA components

| Component | Responsibility | Notes |
|---|---|---|
| Chat UI | Message list, streaming text renderer, input box, interleaved approval cards and navigation toasts. | Stateless visual layer. |
| Browser Turn Orchestrator | State machine driving the turn cycle: send turn → render reply → collect approvals → execute → send results → next turn. Holds the in-memory transcript. | Deep, tested as a reducer. |
| Proposal Executor | Validates [[Tool-Call Proposal]] args against the [[Tool Manifest]], dispatches via [[Tool Registry (Browser)]], applies response projection / 4KB truncation, normalizes results. | Deep, tested with mocked SDK. |
| Tool Registry (Browser) | Static `toolName → (args) => existingSdk.foo.bar(args)` map. | Shallow, data. The seam that lets us reuse the SDK rather than build a parallel HTTP client. |
| Approval Card UI | Per-proposal card. Renders tool name, args (IDs prominent), risk class, approve/decline. Destructive variants add a confirmation gate. | Shallow UI; design-reviewed (issue 08). |
| Navigation Intent Handler | Auto-executes [[Navigation Intent|navigation intents]]: SPA router push + "Taking you to …" toast with undo. | Shallow. |

### 3.2 Chat Service components

| Component | Responsibility | Notes |
|---|---|---|
| Conversation Turn Handler | Lambda entry. Parses request, invokes Agent Loop, streams response via Lambda response streaming. | Shallow, covered transitively by Agent Loop tests. |
| Agent Loop | Calls Bedrock Converse with the composed system prompt + tool definitions + transcript. Parses the model response into `{ assistantText, proposals, navigationIntents }`. On tool-result feedback, continues the loop. | Deep, tested with mocked Bedrock. |
| System Prompt Builder | Composes system prompt: agent role + navigation/scope rules + always-on runbook title index + per-turn user identity context. | Deep, pure. Snapshot-tested. |
| Tool Manifest Validator | Verifies any tool-use block the model emits references an allowlist entry and the args conform. Rejects malformed proposals before they reach the browser. | Sanity, not authz. Deep, table-driven tests. |
| Runbook Retriever | Wraps Bedrock KB `Retrieve` for the `lookupRunbook` tool. | Shallow. |
| Bedrock Client Wrapper | Thin `ConverseStream` wrapper with error normalization. | Shallow. |

### 3.3 Build pipeline

| Component | Responsibility | Notes |
|---|---|---|
| Smithy → Manifest Generator | Build-time tool: consumes Smithy model + allowlist + description overrides, emits the [[Tool Manifest]] consumed by both the chat service and the SPA. Validates allowlist entries exist in Smithy and have descriptions + risk classes. | Deep, fixture-tested. |
| Runbook sync CI | On merge: uploads `/runbooks/*.md` to S3, triggers Bedrock KB ingestion. Validates frontmatter and `tools-referenced`. | Shallow. |

### 3.4 Module dependency map

```mermaid
flowchart TB
    subgraph SPA
        ChatUI[Chat UI]
        Orch[Browser Turn Orchestrator]
        ApprovalCard[Approval Card UI]
        NavHandler[Navigation Intent Handler]
        Executor[Proposal Executor]
        Registry[Tool Registry]
        SDK[Existing Frontend SDK]
    end
    subgraph ChatSvc[Chat Service]
        Handler[Conversation Turn Handler]
        Loop[Agent Loop]
        Prompt[System Prompt Builder]
        Validator[Tool Manifest Validator]
        Retriever[Runbook Retriever]
        BedrockClient[Bedrock Client Wrapper]
    end
    Manifest[(Tool Manifest<br/>build-time JSON)]

    ChatUI --> Orch
    Orch --> ApprovalCard
    Orch --> NavHandler
    Orch --> Executor
    Executor --> Registry
    Executor --> Manifest
    Registry --> SDK

    Handler --> Loop
    Loop --> Prompt
    Loop --> Validator
    Loop --> BedrockClient
    Loop --> Retriever
    Validator --> Manifest
    Prompt --> Manifest
```

---

## 4. Sequence flows

### 4.1 Text-only turn (no tools)

```mermaid
sequenceDiagram
    actor U as User
    participant S as SPA<br/>(Orchestrator)
    participant R as Router
    participant C as Chat Service
    participant B as Bedrock

    U->>S: types message
    S->>S: append to transcript
    S->>R: POST /chat/turn<br/>{transcript, userMessage}
    R->>R: authn/authz
    R->>C: forward + identity
    C->>C: build system prompt
    C->>B: ConverseStream(system, messages, tools)
    B-->>C: stream text tokens
    C-->>S: stream {assistantText}
    S-->>U: render streamed tokens
    Note over S: append assistant turn to transcript
```

### 4.2 Turn with a single tool call (the core HITL flow)

```mermaid
sequenceDiagram
    actor U as User
    participant S as SPA<br/>(Orchestrator)
    participant E as Proposal<br/>Executor
    participant SDK as Frontend SDK
    participant API as Backend API
    participant C as Chat Service
    participant B as Bedrock

    U->>S: "what plan am I on?"
    S->>C: POST /chat/turn {transcript, userMessage}
    C->>B: ConverseStream(..., tools=[manifest])
    B-->>C: tool_use{tool=getCurrentUser, args={}}
    C->>C: validate against manifest
    C-->>S: {proposals=[{id, tool, args, riskClass}]}
    S->>S: render Approval Card
    U->>S: clicks Approve
    S->>E: execute(proposal)
    E->>E: validate args vs manifest
    E->>SDK: sdk.user.getCurrent()
    SDK->>API: GET /me (Bearer access_token)
    API-->>SDK: 200 {name, tier, ...}
    SDK-->>E: response
    E->>E: project/truncate per manifest
    E-->>S: {id, status:"ok", body}
    S->>C: POST /chat/turn {transcript, toolResults=[...]}
    C->>B: ConverseStream(..., tool_result fed back)
    B-->>C: stream text "You're on the Pro plan…"
    C-->>S: stream {assistantText}
    S-->>U: render reply
```

The "suspend / resume" between the proposal emission and the tool-result
feedback is **just two HTTP calls**, not anything exotic. The chat service
is stateless; the browser holds the transcript and replays it each turn.

### 4.3 Turn with a decline

```mermaid
sequenceDiagram
    actor U as User
    participant S as SPA<br/>(Orchestrator)
    participant C as Chat Service
    participant B as Bedrock

    U->>S: "cancel my subscription"
    S->>C: POST /chat/turn
    C->>B: ConverseStream
    B-->>C: tool_use{tool=requestCancellation, args={...}}
    C-->>S: proposals=[{... riskClass:"destructive"}]
    S->>S: render Approval Card (destructive variant, gate)
    U->>S: clicks Decline
    S->>C: POST /chat/turn {toolResults=[{status:"declined"}]}
    C->>B: ConverseStream (sees declined tool_result)
    B-->>C: stream text "OK — I won't proceed. Want me to…?"
    C-->>S: stream assistantText
    S-->>U: render acknowledgement
```

No silent retry. The model is prompted by the system rules to acknowledge
and suggest alternatives or stop — never re-emit the same proposal
unprompted.

### 4.4 Turn with a runbook lookup + multi-step plan

```mermaid
sequenceDiagram
    actor U as User
    participant S as SPA
    participant C as Chat Service
    participant B as Bedrock
    participant KB as Bedrock KB

    U->>S: "cancel my subscription"
    S->>C: POST /chat/turn
    C->>B: ConverseStream
    B-->>C: tool_use{tool=lookupRunbook, query="cancel subscription"}
    C->>KB: Retrieve(query)
    KB-->>C: runbook chunks
    C->>B: ConverseStream (runbook fed back as tool_result)
    B-->>C: text + tool_use{tool=getSubscription, args={}}
    C-->>S: assistantText + proposal
    Note over U,S: ... user approves, browser executes,<br/>result fed back ...
    Note over B: agent chains next step from runbook
    B-->>C: tool_use{tool=requestCancellation, args=...}
    Note over U,S: ... approval + execute ...
    B-->>C: tool_use{tool=getCancellationStatus, args=...}
    Note over U,S: ... approval + execute ...
    B-->>C: stream text "Done — your subscription is cancelled."
```

`lookupRunbook` is **server-executed** (no token needed, no side effect) so
no per-call approval. Every subsequent API call is browser-executed and
individually approved.

### 4.5 Turn with a navigation intent (no tools)

```mermaid
sequenceDiagram
    actor U as User
    participant S as SPA
    participant C as Chat Service
    participant B as Bedrock

    U->>S: "take me to billing"
    S->>C: POST /chat/turn
    C->>B: ConverseStream
    B-->>C: text "Heading to billing…" +<br/>tool_use{tool=navigate, args={url:"/billing"}}
    C-->>S: {assistantText, navigationIntents=[{url}]}
    S-->>U: render text, then toast "Taking you to /billing"
    S->>S: router.push("/billing")
```

Navigation intents auto-execute (no approval) because they mutate only
client state and require no access token.

### 4.6 Turn with an out-of-scope question

```mermaid
sequenceDiagram
    actor U as User
    participant S as SPA
    participant C as Chat Service
    participant B as Bedrock

    U->>S: "what's your refund policy?"
    S->>C: POST /chat/turn
    C->>B: ConverseStream (system prompt: "decline policy Qs, navigate")
    B-->>C: text "Our refund details live on the help center —<br/>let me take you there." +<br/>tool_use{tool=navigate, args={url:"/contact"}}
    C-->>S: {assistantText, navigationIntents=[{url:"/contact"}]}
    S-->>U: render decline + toast + navigation
```

---

## 5. Browser turn orchestrator state machine

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> AwaitingTurn: userTyped / send
    AwaitingTurn --> Streaming: first chunk received
    Streaming --> Streaming: more tokens
    Streaming --> AwaitingApprovals: proposals received
    Streaming --> ExecutingNavigations: navigationIntents received
    Streaming --> Idle: turnComplete, no proposals
    ExecutingNavigations --> Idle: navigation fired
    AwaitingApprovals --> Executing: user approved at least one
    AwaitingApprovals --> AwaitingTurn: all declined → send declines
    Executing --> Executing: more proposals pending
    Executing --> AwaitingTurn: all results gathered → send next turn
    AwaitingTurn --> Error: network / 5xx
    Streaming --> Error: stream aborted
    Error --> Idle: user dismisses
```

States are tested as reducer transitions (deep module). The state machine
is what makes the orchestrator straightforward to test in isolation — no
DOM, no network, just state + events.

---

## 6. Data shapes (contract surface)

These are the contracts between subsystems. Field names are stable; exact
serialization is an implementation detail.

### 6.1 Browser ⇄ Chat Service

**Request** (`POST /chat/turn`)
```
{
  transcript:    Message[]              // full prior conversation
  userMessage?:  string                 // if user just typed
  toolResults?:  ToolResult[]           // if browser just executed proposals
}
```

**Response** (streamed)
```
{
  assistantText:      string            // streamed in chunks
  proposals:          Proposal[]        // emitted whole, after text
  navigationIntents:  NavigationIntent[]
}
```

### 6.2 Proposal & ToolResult

```
Proposal {
  id:        string                     // unique per turn
  tool:      string                     // allowlist entry name
  args:      object                     // conforms to manifest argSchema
  riskClass: "read" | "write" | "destructive"
}

ToolResult {
  id:      string                       // matches Proposal.id
  status:  "ok" | "error" | "declined"
  body?:   unknown                      // projected/truncated tool response
  error?:  { kind: "client" | "server" | "network", message: string, statusCode?: number }
}
```

### 6.3 NavigationIntent

```
NavigationIntent {
  url: string                           // internal path only
}
```

### 6.4 Tool Manifest (build-time JSON)

```
ToolManifestEntry {
  name:              string
  description:       string             // LLM-tuned
  riskClass:         "read" | "write" | "destructive"
  argSchema:         JSONSchema
  responseProjection?: PathSelector[]   // applied before truncation
  maxResponseBytes?: number             // default 4096
}
```

### 6.5 Runbook frontmatter

```
---
name:             string                # kebab-case slug, unique
title:            string                # human-readable
tools-referenced: string[]              # must exist in allowlist
tags:             string[]
last-reviewed:    YYYY-MM-DD
---

<body — short, LLM-tuned procedural prose>
```

---

## 7. Build & sync pipelines

### 7.1 Tool Manifest generation (build time)

```mermaid
flowchart LR
    Smithy[(Smithy model)]
    Allow[(allowlist.json)]
    Desc[(descriptions.json<br/>LLM-tuned overrides)]
    Gen[Smithy → Manifest<br/>Generator]
    Manifest[(tool-manifest.json)]
    SPA[SPA bundle]
    Chat[Chat Service bundle]

    Smithy --> Gen
    Allow --> Gen
    Desc --> Gen
    Gen -->|validate: allowlisted ops exist,<br/>descriptions present, risk classes present| Manifest
    Manifest --> SPA
    Manifest --> Chat
```

Single source of truth for the agent's catalog. Build fails if validation
fails — no silent drift.

### 7.2 Runbook KB sync (on merge to main)

```mermaid
flowchart LR
    Repo[/runbooks/*.md/]
    CI[CI step]
    S3[(S3 prefix)]
    Ingest[KB ingestion job]
    KB[Bedrock KB]

    Repo -->|push to main| CI
    CI -->|validate frontmatter +<br/>tools-referenced ⊂ allowlist| CI
    CI -->|upload changed files| S3
    CI -->|start-ingestion-job| Ingest
    Ingest --> KB
```

KB ingestion takes minutes. Runbook updates are not real-time; the
authoring tempo (PR → review → merge → ingest) is acceptable for v1.

---

## 8. Security model

The full reasoning is in [ADR 0001](./docs/adr/0001-agent-is-a-ui-not-a-trust-boundary.md). Summary:

- **The access token never leaves the browser.** It is attached only when
  the SPA's Proposal Executor invokes the existing frontend SDK, exactly
  as the SPA does for any user-initiated click. The chat service does not
  receive it; Bedrock does not receive it.
- **The agent is a UI, not a trust boundary.** The backend API's existing
  per-call authz checks are the sole authorization gate. Anything the user
  can do via clicks, they can do via the agent; anything they can't do
  via clicks, the API will reject when the agent tries.
- **HITL is defense-in-depth against social engineering**, not against
  privilege escalation. The user can be tricked (e.g., via a prompt-injected
  tool result) into approving something they could legitimately do but
  shouldn't. The approval card UX is the mitigation: IDs prominent, risk
  class shown, destructive operations gated.
- **No server-side re-validation of proposals against user permissions.**
  Duplicating the API's checks would be a parallel authz system that can
  drift — a *worse* posture than relying on the API.

### 8.1 What the LLM sees vs doesn't see

```mermaid
flowchart LR
    subgraph llm[LLM sees]
        sys[System prompt]
        trans[Transcript]
        toolDefs[Tool definitions<br/>names + arg schemas + descriptions]
        toolRes[Tool result bodies<br/>projected/truncated]
        runbook[Retrieved runbook chunks]
    end
    subgraph never[LLM never sees]
        token[Access token]
        rawResp[Raw unprojected API responses<br/>over 4KB]
        otherUser[Any other user's data]
    end

    classDef good fill:#dfe;
    classDef bad fill:#fdd;
    class llm good;
    class never bad;
```

---

## 9. Failure modes & their handling

| Failure | Detection | Handling |
|---|---|---|
| Model emits a tool name not in allowlist | Tool Manifest Validator (server) | Reject before sending to browser; log; the Agent Loop tells the model "that tool doesn't exist" and continues. |
| Model emits args that violate the manifest schema | Tool Manifest Validator (server) | Same as above. |
| User declines a proposal | Browser Orchestrator | Send `{status:"declined"}` back; model is prompted to acknowledge and suggest alternatives or stop. |
| Backend API returns 4xx | Proposal Executor | Normalize to `{status:"error", error:{kind:"client", ...}}`; fed back; model may propose differently. **No auto-retry.** |
| Backend API returns 5xx | Proposal Executor | Same as 4xx with `kind:"server"`. **No auto-retry.** |
| Network/timeout in browser | Proposal Executor | Surface in chat UI with "try again" affordance; user must re-approve to retry. |
| Tool response exceeds 4KB | Proposal Executor | Apply per-tool `responseProjection` first; if still over, truncate with `…truncated, N more bytes` note. |
| Bedrock returns an error | Bedrock Client Wrapper | Surface to user as "something went wrong with the assistant"; no auto-retry; turn ends. |
| Lambda response stream interrupted | Browser Orchestrator | Mark partial turn as failed; user can resend. |
| Runbook KB retrieval fails | Runbook Retriever | Return empty result + log; model is told "no runbook found" and proceeds without one. |
| Conversation grows past comfortable token count | (Logged, not enforced in v1) | No action in v1. Watch logs; revisit if real conversations exceed ~50K tokens. |

---

## 10. Deployment

```mermaid
flowchart LR
    subgraph aws[AWS]
        CF[CloudFront]
        FU[Lambda Function URL<br/>response streaming]
        L[Chat Service Lambda]
        BR[Bedrock Converse]
        KB[Bedrock KB]
        S3[(S3 — runbook source)]
        CW[CloudWatch]
        IAM[IAM execution role]
    end
    SPA[React SPA<br/>existing app]
    Router[Existing Router Service]

    SPA --> Router
    Router --> CF
    CF --> FU
    FU --> L
    L --> BR
    L --> KB
    L -.-> CW
    S3 -.-> KB
    L -.- IAM
```

- **Lambda** with response streaming via Function URL, fronted by
  CloudFront for caching headers and a stable hostname. The existing
  Router Service forwards authenticated traffic to CloudFront.
- **IAM**: Lambda role allows `bedrock:InvokeModelWithResponseStream`,
  `bedrock-agent-runtime:Retrieve`, and CloudWatch Logs writes. No other
  AWS API access. No access to user data stores — by construction, the
  chat service does not need them.
- **CDK app** is the source of truth for all of the above; one stack per
  environment.

---

## 11. Open trade-offs and known risks

| Trade-off | Decision | Future revisit signal |
|---|---|---|
| Browser-held transcript | Accepted; ships v1 fast | Users ask for cross-device resume; or support requests transcript access |
| No rate limits / cost budgets | Accepted; bounded risk via Cognito-only access | First abuse incident; or any non-trivial public rollout |
| No transcript persistence | Accepted | Support needs to review user sessions; compliance requires retention |
| Single model (Haiku 4.5) | Cost-first start | Quality complaints on multi-step tasks → escalate to Sonnet 4.6 |
| No model-evals | Accepted; small v1 surface area | Runbook count grows past ~20 or retrieval quality drops |
| No macro-tools | Accepted; primitive chaining + per-call HITL | Approval fatigue measured in user research |
| No product-docs KB | Accepted; navigate-and-handoff | If a significant fraction of user queries are declined, build the KB |
| Out-of-scope = decline-and-navigate | Accepted | Liability cost of one wrong answer ≫ inconvenience of navigation |

Each of these has a tracked deferral in PRD §"Out of Scope." None are
oversights.

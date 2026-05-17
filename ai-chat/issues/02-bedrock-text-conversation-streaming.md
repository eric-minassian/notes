# 02 — Real Bedrock conversation, text-only, streaming

**Type**: AFK
**Label**: ready-for-agent

## What to build

Replace the echo in issue 01 with a real Bedrock Converse call. The agent can
now hold a streaming text-only multi-turn conversation with the user. No
tools, no navigation, no runbooks yet.

- Bedrock Client Wrapper: thin wrapper around `ConverseStream` for Claude
  Haiku 4.5. Normalizes errors.
- System Prompt Builder (minimal v1): emits a static system prompt with the
  agent's role and a placeholder for the per-turn user identity context. No
  runbook index yet, no tool taxonomy yet.
- Agent Loop (minimal v1): assembles `{ system, messages }` from the request,
  calls Bedrock, streams the text response back through Lambda response
  streaming. No tool-use handling yet.
- Conversation Turn Handler: streams the assistant reply back to the
  browser; the browser appends streamed tokens to the in-progress message.
- Browser Turn Orchestrator (text-only v1): manages the request/response
  cycle and the streaming-token append.

Tests (per PRD testing decisions): Agent Loop with mocked Bedrock,
System Prompt Builder snapshot tests.

## Acceptance criteria

- [ ] User sends a message and sees Claude's reply stream in token-by-token.
- [ ] Multi-turn conversation works: the model has access to prior turns
      because the browser replays the transcript on each request.
- [ ] System prompt includes the user's identity context (name, tier) but
      not anything sensitive.
- [ ] Bedrock errors surface to the user as a clear "something went wrong"
      message; no client-side crash.
- [ ] Agent Loop tests pass with mocked Bedrock for at least: empty
      transcript, multi-turn transcript, Bedrock error.
- [ ] System Prompt Builder tests pass for representative identity contexts.

## Blocked by

- 01-hello-world-chat-panel-and-echo-backend

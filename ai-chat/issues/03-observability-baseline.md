# 03 — Observability baseline

**Type**: AFK
**Label**: ready-for-agent

## What to build

Structured logs, metrics, and tracing for every chat turn — landed before
the tool-loop work so we can debug it. Logs the **shape** of every turn,
never the **content** (no plaintext user messages, no tool-result payloads).

- Structured CloudWatch logs: one log line per turn with `conversationId`,
  `userId`, `tokensIn`, `tokensOut`, `latencyMs`, `bedrockRequestId`, and
  message-shape counts (number of user / assistant / tool-use / tool-result
  blocks). No plaintext.
- CloudWatch metrics: turns-per-user, tokens-in / tokens-out, end-to-end
  turn latency, Bedrock error count. Per-user dimensions for cost
  attribution.
- AWS X-Ray tracing on the chat Lambda, instrumented through to the
  Bedrock client call.

## Acceptance criteria

- [ ] Every turn produces exactly one structured log line in CloudWatch
      with the fields above.
- [ ] CloudWatch metrics exist and update in real-time as turns are
      processed.
- [ ] An X-Ray trace for a single turn shows the Lambda invocation and the
      Bedrock subsegment.
- [ ] Smoke test: ten conversations from two different users produce
      distinguishable entries in logs and per-user metric dimensions.
- [ ] No log line contains user message text, system prompt text, or model
      output text.

## Blocked by

- 02-bedrock-text-conversation-streaming

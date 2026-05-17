# 01 — Hello-world: chat panel → backend → echo

**Type**: HITL
**Label**: ready-for-agent

## What to build

The minimum end-to-end vertical slice that proves the deployment topology and
auth wiring work. A logged-in user clicks a chat button in the SPA, types a
message, and receives a hardcoded reply from the [[Chat Service]]. No Bedrock
calls yet; no tools yet; no streaming yet. The point is to land the infra and
the auth path.

Stand up:

- A new [[Chat Service]] Lambda behind the existing router service so it
  inherits route-based authn/authz. The Lambda accepts a request body of
  `{ transcript, userMessage }` and returns `{ assistantText: "<echo of input>" }`.
- A CDK app provisioning the Lambda, its Function URL (configured for response
  streaming, even though we are not streaming yet), CloudFront in front of the
  Function URL, and the IAM execution role.
- A chat UI surface in the SPA: a floating button to open a panel, a message
  list, an input box, a send button. Plain styling is fine; this is plumbing.

The browser sends `{ transcript: [...prior turns], userMessage: "..." }` and
appends the assistant reply to its own in-memory transcript. No persistence.

This slice is marked HITL because the first infra deploy and the IAM /
CloudFront / Function URL wiring deserve human review before merge.

## Acceptance criteria

- [ ] Logged-in user can open the chat panel from anywhere in the SPA.
- [ ] User can type and send a message; the assistant's hardcoded reply
      appears in the message list.
- [ ] Multi-turn works: previous messages remain visible and the transcript
      is sent with each request.
- [ ] Anonymous (logged-out) request to the chat endpoint is rejected by the
      router service.
- [ ] CDK app deploys cleanly to a non-prod environment.
- [ ] No access token, message content, or response content is logged to
      CloudWatch.

## Blocked by

None — can start immediately.

# 04 — Navigation intents end-to-end

**Type**: AFK
**Label**: ready-for-agent

## What to build

The agent gains the ability to navigate the user to internal URLs without
requiring approval. Per CONTEXT.md, navigation intents auto-execute (with a
toast for transparency) because they touch only client-side state and
require no access token.

- Add a `navigate` tool to Bedrock's tool definitions with a single `url`
  parameter (string, internal-path only — no external URLs in v1).
- Chat service forwards `navigate` tool-use blocks as
  `NavigationIntent { url }` in the streamed response.
- System Prompt Builder gains the navigation-vs-API taxonomy guidance: when
  the user wants to go somewhere on the site, emit a `navigate`.
- Navigation Intent Handler (browser): on receipt, calls the SPA router and
  shows a transient "Taking you to …" toast with an undo affordance
  (`history.back()`).
- Browser Turn Orchestrator: handles `navigationIntents[]` alongside text.

Tests: System Prompt Builder snapshot updated; Agent Loop test for the
"text + navigation intent" response shape; Browser Turn Orchestrator
reducer test for the navigation event.

## Acceptance criteria

- [ ] "Take me to billing" sends the user to the billing page with a toast.
- [ ] Toast offers an undo that returns the user to the previous page.
- [ ] Navigation intents are auto-executed without an approval card.
- [ ] External URLs (anything not starting with the app's own path prefix)
      are rejected client-side rather than navigated to.
- [ ] When the agent emits both streamed text and a navigation intent in
      one turn, the text renders first and the navigation fires after the
      text settles.

## Blocked by

- 02-bedrock-text-conversation-streaming

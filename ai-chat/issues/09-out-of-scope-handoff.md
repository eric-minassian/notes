# 09 — Out-of-scope handoff (policy/pricing → navigate)

**Type**: AFK
**Label**: ready-for-agent

## What to build

Teach the agent to recognize out-of-scope questions (policy, pricing,
plans, legal, anything declarative that would be a liability to
hallucinate) and respond with a brief decline + a navigation intent to the
relevant page (pricing, docs, or contact-us as the fallback). Per
CONTEXT.md, this is the v1 stand-in for a product-documentation knowledge
base — we choose not to answer rather than risk a hallucinated answer.

- System Prompt Builder gains the "decline policy/pricing/legal, navigate
  instead" rule with a small set of worked examples.
- A short reference table of "topic → destination URL" the agent can
  reason over (pricing page, docs root, contact-us, etc.). Inline in the
  system prompt; no KB lookup needed for this in v1.
- A short script of `(prompt, expected_behavior)` fixtures the Agent Loop
  tests can assert against (declines politely, emits the right
  navigation intent, does not invent an answer).

## Acceptance criteria

- [ ] "What's your refund policy?" → agent declines + navigates to
      contact-us (or the appropriate destination).
- [ ] "What's the difference between Pro and Business?" → agent declines
      + navigates to pricing.
- [ ] "How do I cancel my subscription?" (procedural, in-scope) still
      goes through the normal runbook + tool-call flow rather than being
      caught by the decline rule.
- [ ] Agent Loop tests cover the decline-and-navigate behavior for at
      least three representative prompts.

## Blocked by

- 04-navigation-intents-end-to-end

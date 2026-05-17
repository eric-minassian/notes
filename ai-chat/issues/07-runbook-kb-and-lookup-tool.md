# 07 — Runbook KB + `lookupRunbook` tool

**Type**: AFK
**Label**: ready-for-agent

## What to build

The agent gains procedural knowledge through [[Runbook|runbooks]] stored in
a Bedrock Knowledge Base and retrieved on demand via an explicit
`lookupRunbook` tool. Per CONTEXT.md, retrieval is *deliberate* (a model
call), not automatic at every turn — this keeps retrievals visible in logs.

- Infra (CDK): S3 bucket for runbook source, Bedrock Knowledge Base
  pointed at that bucket, default Titan/Cohere embedder, default chunking.
- Runbook Retriever (chat service): wraps Bedrock KB `Retrieve` for the
  `lookupRunbook` tool implementation. Server-executed (not browser-side)
  because it does not require the user's access token and produces no
  external side effect.
- Add `lookupRunbook` as a Bedrock tool definition. Auto-executed on the
  server with no per-call approval (it is informational, equivalent to
  the agent thinking out loud).
- Runbook frontmatter schema enforced in CI: `name`, `title`,
  `tools-referenced`, `tags`, `last-reviewed`.
- CI validations: every `tools-referenced` value exists in the allowlist;
  every write/destructive allowlisted tool is covered by at least one
  runbook (lint-level warning in v1, hard fail in p1).
- CI sync step: on merge to main, upload `/runbooks/*.md` to S3 and
  trigger a Bedrock KB ingestion job.
- System Prompt Builder gains the always-on runbook index: title + one-line
  summary for each runbook (per CONTEXT). Keep it short.
- Author 2–3 example runbooks covering real multi-step tasks (e.g., a
  cancel-subscription flow, a billing-update flow).

## Acceptance criteria

- [ ] Asking for a multi-step task triggers a `lookupRunbook` call visible
      in logs, then a sequence of proposals matching the runbook's steps.
- [ ] Merging a PR that adds a runbook causes it to appear in the KB
      within the ingestion job's runtime, without manual intervention.
- [ ] System prompt size remains bounded — runbook index entries are titles
      + one-liner, not full bodies.
- [ ] CI fails a PR whose runbook references a tool not on the allowlist.
- [ ] Runbook frontmatter schema is enforced in CI; malformed runbooks fail
      the build.

## Blocked by

- 06-smithy-to-manifest-generator

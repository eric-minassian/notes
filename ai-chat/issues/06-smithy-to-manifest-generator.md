# 06 — Smithy → Manifest Generator

**Type**: AFK
**Label**: ready-for-agent

## What to build

Replace issue 05's hand-written [[Tool Manifest]] JSON with a build-time
generator. Sources of truth: (a) the Smithy model (for shapes), (b) a
hand-curated allowlist file (the names of allowed operations + risk
classes), (c) a hand-curated description-overrides file (LLM-tuned
descriptions, since Smithy `@documentation` is written for SDK users).

- Generator consumes Smithy + allowlist + descriptions and emits the same
  manifest shape issue 05 already consumes. Deterministic.
- Build-time validations (fail the build):
  - Every allowlisted operation exists in the Smithy model.
  - Every allowlisted entry has a description override (no defaults — force
    the curation step).
  - Every entry has a risk class.
- Expand the allowlist to roughly 5–10 read operations to validate the
  generator handles variety.
- Wire the generator into the existing build pipeline so the manifest is
  regenerated whenever Smithy or the allowlist changes.

Tests (deep module): fixture-driven — given a small Smithy model and an
allowlist, assert the emitted manifest. Cover all the failure modes
(missing op, missing description, missing risk class, allowlist references
unknown op).

## Acceptance criteria

- [ ] Running the build regenerates the manifest from current Smithy +
      allowlist.
- [ ] All deterministic-output tests pass with fixture Smithy inputs.
- [ ] Each build-time validation rule fails the build with a clear error
      message when violated.
- [ ] Agent successfully uses at least 3 of the newly allowlisted tools
      end-to-end via the issue 05 flow, with no code changes between
      tools.
- [ ] The hand-written JSON manifest from issue 05 is deleted; the
      generator is the sole source.

## Blocked by

- 05-first-end-to-end-tool-call

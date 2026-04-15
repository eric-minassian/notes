# Research Notes

This is a personal knowledge base. Each research session produces a self-contained folder of notes.

## Structure

```
notes/
├── CLAUDE.md          ← you are here
├── topic-name/
│   └── index.md
├── another-topic/
│   └── index.md
```

- **One folder per topic.** Name it with kebab-case (e.g., `cap-theorem`, `raft-consensus`).
- **Entry point is always `index.md`.** You may create additional markdown files in the folder if the topic is large, but `index.md` is required and serves as the main document.
- **Stay in your folder.** Do not modify files outside the folder you create. Do not touch this CLAUDE.md, other topic folders, or repo config.

## Frontmatter (required)

Every `index.md` must start with:

```yaml
---
title: "Human-Readable Title"
description: "One-line summary of what this covers."
date: YYYY-MM-DD
tags: ["tag1", "tag2"]
---
```

- `date` is the date the research was conducted.
- `tags` should be lowercase, general categories (e.g., `distributed-systems`, `databases`, `algorithms`).

## Content guidelines

- Use clear headings to organize sections.
- Use **Mermaid** diagrams (` ```mermaid `) for any visual concepts — architecture, flows, sequences, state machines, etc. Prefer diagrams over long textual descriptions when a visual would be clearer.
- Write for future reference: assume the reader (me) has context on the general domain but hasn't looked at this specific topic recently.
- Include practical takeaways, tradeoffs, and "when to use this" guidance where applicable.
- Link to authoritative sources where relevant.

## What NOT to do

- Don't create README.md files.
- Don't modify anything outside your topic folder.
- Don't use HTML — stick to standard markdown and mermaid.

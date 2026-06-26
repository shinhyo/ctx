---
name: ctx-agent-history-search
description: Use ctx to search local coding-agent history before acting. Use when prior agent sessions may contain relevant commands, attempts, decisions, source citations, or transcript context.
---

# ctx Agent History Search

Use ctx as a local retrieval tool before repeating investigation work. Treat ctx
output as cited source material from local transcripts, not as generated
analysis.

## Prerequisites

- Require the `ctx` CLI to be installed and set up.
- Start with `ctx status --json`.
- If `ctx` is missing or not set up, tell the user the local history index is
  unavailable and do not invent results.

## Workflow

1. Check health:

   ```bash
   ctx status --json
   ```

2. Inspect available provider sources:

   ```bash
   ctx sources --json
   ```

3. Re-import only when recent local history matters or search misses something
   the user says should exist:

   ```bash
   ctx import --all --json
   ctx import --resume --json
   ```

   Treat `--resume` as an idempotent rescan marker, not a guarantee that every
   provider has native cursor resume.

4. Search with tight filters whenever possible:

   ```bash
   ctx search "<query>" --json
   ctx search "<query>" --provider codex --json
   ctx search "<query>" --repo <repo> --json
   ctx search "<query>" --file <path> --json
   ctx search "<query>" --since 30d --json
   ```

5. Inspect the best cited result before relying on it:

   ```bash
   ctx show event <ctx-event-id> --window 5 --format json
   ctx show session <ctx-session-id> --mode lite --format json
   ```

6. Locate original provider material when source identity or resume hints matter:

   ```bash
   ctx locate event <ctx-event-id> --format json
   ctx locate session <ctx-session-id> --format json
   ```

7. Export a transcript only when another agent or artifact needs a file:

   ```bash
   ctx export session <ctx-session-id> --mode lite --format markdown --out /tmp/ctx-session.md
   ```

## Citation Rules

- Cite ctx material when it affects your answer or implementation.
- Include the provider, ctx session ID, ctx event ID when available, provider
  session ID when available, and source path or cursor when present.
- If you synthesize across multiple snippets, label the conclusion as your
  synthesis and cite the supporting snippets.
- If a source citation is stale or unavailable, say ctx returned indexed text
  but the raw source could not be opened.

## Safety Rules

- Prefer JSON for ranking and routing.
- Do not say ctx inferred a decision unless the cited text explicitly states
  that decision.
- Do not state that ctx wrote model analysis.
- Treat `~/.ctx`, provider transcript paths, and JSON output as private local
  history unless the user explicitly asks to share reviewed excerpts.
- Use typed IDs. Do not fall back to old ambiguous `ctx show <uuid>` behavior.

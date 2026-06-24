# Search And Context

ctx has two retrieval commands:

- `ctx search` finds matching indexed sessions and events.
- `ctx context` builds a bounded retrieval bundle for an agent.

Both commands read the local SQLite store and write nothing.

## Search

Examples:

```bash
ctx search "build failure"
ctx search "sqlite storage" --provider codex
ctx search "retry handling" --repo checkout --since 60d
ctx search "tool output" --event-type tool_output
ctx search --file crates/foo/src/lib.rs
ctx search "token budget" --limit 5 --json
```

A result can include:

- an opaque item ID usable with `ctx show`;
- title or event label;
- snippet with redaction and truncation where needed;
- rank and match reasons;
- provider;
- session ID;
- event ID or event sequence;
- timestamp;
- working directory when known;
- source path and cursor when available;
- source availability flag when known;
- citations.

## Filters

Search filters narrow both human output and JSON:

- `--provider codex|pi`;
- `--repo <name-or-path>`;
- `--since <rfc3339-or-days>d`;
- `--event-type <event-type>`;
- `--file <path>`;
- `--primary-only`;
- `--include-subagents`;
- `--limit <n>`.

`--since` accepts RFC 3339 timestamps such as `2026-06-01T00:00:00Z` or a day
window such as `30d`.

The default includes subagent material. `--primary-only` excludes it unless
`--include-subagents` is also passed.

## Context

`ctx context` is deterministic retrieval. For the same database, query, filters,
limit, and token budget, it should select the same material in the same order.

Examples:

```bash
ctx context "checkout retry"
ctx context "checkout retry" --max-tokens 6000
ctx context "checkout retry" --provider codex --since 30d
ctx context "checkout retry" --event-type command_output --json
```

Context output includes:

- query and filters;
- token budget and estimated returned tokens;
- selected results;
- snippets or source excerpts;
- provider, date, working-directory, session, and event metadata when known;
- citations back to indexed items and raw source paths when available;
- pagination and truncation metadata.

It respects the requested token budget by omitting lower-ranked material or
dropping result text while preserving citation metadata when possible.

## Citation Format

Human context output prints citations as list items:

```text
- event <event-id> provider=codex session=<session-id> event_seq=<n> source=<path> cursor=<cursor>
```

JSON context output carries the same pieces as structured fields. A citation
with `source_exists: false` means ctx can return indexed text, but the raw
provider file was not available at the stored path when the result was built.

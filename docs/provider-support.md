# Provider Support

This public `0.1.0` candidate preview uses a strict provider taxonomy. Do not
call a provider "supported" unless it has at least supported-import or
supported-wrapper proof with reviewable output and docs that match the actual
implementation.

This branch proves provider integration through explicit, local import commands
and a conservative local discovery command. It does not install passive Codex,
Claude Code, or Pi native hooks. The first shipped passive capture surface is
the local Git/jj/gh wrapper shim path installed by `ctx setup`.

Authoritative machine-readable metadata lives in
`docs/provider-support-matrix.json`. The shared provider adapter and normalized
envelope contract is described in `docs/provider-adapter-api.md` and backed by
typed `work-record-core` provider structs.

The public release taxonomy uses hyphenated labels. The current
machine-readable metadata serializes equivalent implementation status ids in
snake_case where needed, such as `supported_import` and `fixture_only`.

## Taxonomy

| Public status | Metadata id | Public meaning |
| --- | --- | --- |
| `supported-live` | `supported_live` | Native or wrapper capture, real live proof, review surfaces, and gated evidence are all green. |
| `supported-import` | `supported_import` | Stable existing-history import is proven, but passive live capture is unavailable or intentionally not implemented yet. |
| `supported-wrapper` | `supported_wrapper` | ctx can capture the surface through a wrapper or shim even when native provider hooks are unavailable. |
| `fixture-only` | `fixture_only` | Normalized fixture import works, but no real provider data is proven in the public candidate yet. |
| `detected-unsupported` | `detected_unsupported` | ctx can detect a local install or directory, but there is no safe import or capture path to claim publicly. |
| `blocked` | `blocked` | A concrete blocker exists and needs provider-specific proof before the public docs can upgrade the claim. |

## Current candidate matrix

| Provider | Current status | Implemented path | Source format | Fidelity | Captured | Not captured | Proof |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Codex | `fixture_only` | `ctx capture import-provider --provider codex --input <fixture.jsonl>` | normalized provider fixture JSONL | imported | sessions, events, exposed parent-child session edges, cursors, source metadata | native history discovery, assistant/tool fidelity beyond fixture content | `tests/fixtures/provider/codex.jsonl`; capture and CLI tests |
| Codex | `supported_import` | `ctx capture import-codex-history --input ~/.codex/history.jsonl` or `ctx capture import-local-providers` | Codex prompt history JSONL with `session_id`, `ts`, `text` | summary_only | user prompt events grouped by Codex session id | assistant replies, tool calls, command output, artifacts, child session relationships | `tests/fixtures/provider-history/codex-history.jsonl`; capture and CLI tests; local blocker notes below |
| Claude Code | `fixture_only` | `ctx capture import-provider --provider claude --input <fixture.jsonl>` | normalized provider fixture JSONL | imported | sessions, events, cursors, source metadata present in fixture | native Claude Code history discovery, hooks, live capture | `tests/fixtures/provider/claude.jsonl`; capture and CLI tests |
| Pi | `fixture_only` | `ctx capture import-provider --provider pi --input <fixture.jsonl>` | normalized provider fixture JSONL | imported | sessions, events, source metadata present in fixture, secret-key redaction in metadata | native Pi history discovery, hooks, live capture | `tests/fixtures/provider/pi.jsonl`; capture and CLI tests |

`ctx capture import-local-providers` checks known local locations:

- Codex: `~/.codex/history.jsonl`; imported idempotently as prompt history when present.
- Claude Code: `~/.claude/projects` or `~/.claude`; reported as
  `detected_unsupported` when present because no native Claude Code transcript
  parser or hook is implemented.
- Pi: `~/.pi/agent` or `~/.pi`; reported as `detected_unsupported` when
  present because no native Pi transcript/history parser or hook is implemented.

The command is intentionally conservative. It imports only the sources this
branch can prove safely and refuses to upgrade unsupported providers into
invented capture claims.

## Broader provider work not yet claimed here

The metadata file also carries blocked or classification-pending rows for
Cursor, OpenCode, Gemini CLI, Antigravity CLI, Copilot CLI, Factory/Droid,
Goose, Amp, OpenHands, cagent, Qwen, Mistral, Kimi, Aider, Cline/Roo,
Continue/Cody, Auggie, Junie, Kilo, SWE-agent, and legacy ADE surfaces. Do not
treat those providers as publicly supported based on this branch alone. Until
real import or capture proof lands with matching docs, keep those entries at
`blocked`, `fixture-only`, or `detected-unsupported`.

## Source and Fidelity Metadata

Imported provider rows record `source_format`, source trust, raw-retention
mode, redaction boundary, cursor checkpoints, and explicit idempotency fields
in sync metadata. Normalized fixture imports use
`normalized_provider_fixture_jsonl` and `fidelity=imported`. Codex
prompt-history imports use `codex_history_jsonl` and `fidelity=summary_only`.

The Codex history path intentionally does not create parent/child edges. The
local history format observed for this branch exposes prompt log rows only, not
subagent relationships.

## Shared Provider Contract

Provider workers should normalize native inputs into
`work_record_core::ProviderCaptureEnvelope` values and then persist them through
`work_record_capture::import_normalized_provider_captures`. That common path
owns:

- session/event/source normalization;
- provider event idempotency via provider/session/index/hash dedupe keys;
- cursor checkpoint persistence in `sync_cursors`;
- redaction sanitization before provider payload or metadata is stored;
- shared session-edge creation for parent/child relationships.

`work_record_capture::ProviderFixtureJsonlAdapter` and
`work_record_capture::CodexHistoryJsonlAdapter` are the reference adapters in
this branch.

## Local E2E Evidence and Blockers

Local provider inventory on 2026-06-23:

- Codex: `/home/daddy/.codex/history.jsonl` exists and contains prompt-history
  JSONL rows with `session_id`, `ts`, and `text`. This validates the gated
  parser shape, but the real file is private local data and was not committed.
- Claude: `/home/daddy/.claude` was not present, so native Claude history E2E
  could not run.
- Pi: `/home/daddy/.pi/agent/auth.json` was present, but no local Pi transcript
  or history file was found under `/home/daddy/.pi` within four directory
  levels, so native Pi history E2E could not run.

Gated real-data check for Codex:

```bash
CTX_DATA_ROOT="$(mktemp -d)" \
  ctx capture import-codex-history --input "$HOME/.codex/history.jsonl" --json
```

Run this only on a machine where importing local prompt history into a temporary
ctx data root is acceptable. The output should report `source_format:
codex_history_jsonl`, `fidelity: summary_only`, and limitations explaining that
assistant replies, tools, command output, and child sessions are not present.

Gated real-data checks for Claude and Pi remain blocked until their native
history locations and schemas are available. Until then, only the normalized
fixture adapters are proven.

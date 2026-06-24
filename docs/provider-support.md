# Provider Support

Provider support is intentionally conservative. A provider is documented as
locally importable only when the public CLI can read existing local history for
that provider.

## Status Meanings

| Status | Meaning |
| --- | --- |
| `local_import` | The CLI can import an existing local history source for this provider. |
| `local_import_when_supported` | The CLI has an importer for a specific local format, but support depends on that file existing and matching the documented format. |
| `fixture_only` | The repository has sanitized fixture coverage, but the public CLI does not discover or import native local history for that provider. |
| `detected_unsupported` | The CLI can detect something about the provider but intentionally does not import it. |
| `blocked` | No shipped discovery or import path exists. |

## Current Matrix

Machine-readable provider metadata lives in
[provider-support-matrix.json](provider-support-matrix.json). The public truth
is:

| Provider | Status | Public import path | Live E2E lane |
| --- | --- | --- | --- |
| Codex | `local_import` | `~/.codex/sessions`, `~/.codex/history.jsonl`, or an explicit Codex path. | Manual opt-in local-history smoke. |
| Pi | `local_import_when_supported` | `~/.pi/sessions.jsonl` or an explicit Pi JSONL path. | Manual opt-in local-history smoke. |
| Claude | `fixture_only` | No native local importer in the public CLI. | Blocker artifact only. |
| OpenCode | `fixture_only` | No native local importer in the public CLI. | Blocker artifact only. |
| Antigravity | `fixture_only` | No native local importer in the public CLI. | Blocker artifact only. |
| Gemini | `fixture_only` | No native local importer in the public CLI. | Blocker artifact only. |
| Cursor | `fixture_only` | No native local importer in the public CLI. | Blocker artifact only. |

## Manual Live E2E

Live provider E2E is not part of default CI. It is a manual, non-publishing,
local-history import proof for Codex and Pi only.

Required guardrails:

- set `CTX_LIVE_PROVIDER_E2E=1`;
- set `CTX_LIVE_PROVIDER_ACCEPT_LOCAL_HISTORY=1`;
- select `CTX_LIVE_PROVIDER_CODEX=1` or `CTX_LIVE_PROVIDER_PI=1`;
- provide `CTX_LIVE_PROVIDER_CODEX_SESSIONS_PATH` or
  `CTX_LIVE_PROVIDER_PI_SESSIONS_PATH`;
- use a temporary `CTX_DATA_ROOT`;
- do not execute provider CLIs;
- do not pass API-key environment variables to `ctx`;
- write only redacted aggregate `live-e2e.json` and `live-e2e.md` artifacts.

Codex may also set `CTX_LIVE_PROVIDER_CODEX_HISTORY_PATH`. Codex and Pi may set
a provider-specific query variable, but the raw query must not be written to
artifacts.

The artifacts intentionally omit raw transcripts, snippets, queries, and source
paths. Fixture-only providers write blocked artifacts until a native read-only
local importer ships.

The Bazel provider-live wrapper does not build `ctx` for skipped or fixture-only
blocker lanes. A true Codex or Pi local-history live run may build or use the
selected `ctx` binary, but the runtime flow invokes only `ctx setup`, `ctx
import`, `ctx search`, `ctx context`, `ctx status`, `ctx doctor`, and `ctx
validate` with a scrubbed environment. Provider CLIs, provider API keys, and
provider network credentials are not used by those lane commands.

## Required Evidence For Promotion

Before a provider moves beyond `fixture_only` or `blocked`, the change needs:

- a documented local source format;
- read-only source discovery or an explicit `--path` contract;
- malformed-input tests;
- idempotent re-import tests;
- source citation fields in search/context output;
- storage and redaction notes for provider-specific sensitive fields;
- a redacted live E2E artifact when claiming live local-history support;
- docs updates in this file and `provider-support-matrix.json`.

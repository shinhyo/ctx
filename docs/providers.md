# Providers

ctx imports existing agent history through provider adapters. Each adapter must
make a narrow, testable claim about the source format it reads and the event
fields it indexes.

## Supported Local Imports

The current CLI imports local history for:

- Codex session JSONL trees under `~/.codex/sessions`;
- Codex `~/.codex/history.jsonl`;
- Pi `~/.pi/sessions.jsonl` when that local file exists and matches the
  supported JSONL format.

Use `ctx sources` for the truth on the current machine:

```bash
ctx sources
ctx sources --json
```

If a provider is not listed by `ctx sources`, the current CLI does not discover
or import that provider's native history.

## Fixture-Only Providers

The repository includes normalized fixtures for Claude, OpenCode,
Antigravity, Gemini, and Cursor provider shapes. Those fixtures are useful for
adapter contracts and tests, but they are not native local importers in the
public CLI.

Do not document one of these providers as locally importable until the CLI can
discover or import that provider's real local history and the provider support
matrix marks the shipped path accordingly.

## Live Provider E2E

Live provider E2E is an opt-in local-history import smoke, not a provider
runner. The lane never executes provider CLIs, never passes API-key environment
variables to `ctx`, and runs `ctx` with a temporary `CTX_DATA_ROOT`.

Only Codex and Pi have live E2E lanes because those are the providers with
native local import paths in the public CLI. A live run requires
`CTX_LIVE_PROVIDER_E2E=1`, `CTX_LIVE_PROVIDER_ACCEPT_LOCAL_HISTORY=1`, the
provider selector (`CTX_LIVE_PROVIDER_CODEX=1` or `CTX_LIVE_PROVIDER_PI=1`),
and an explicit local history path:

```bash
CTX_LIVE_PROVIDER_E2E=1 \
CTX_LIVE_PROVIDER_ACCEPT_LOCAL_HISTORY=1 \
CTX_LIVE_PROVIDER_CODEX=1 \
CTX_LIVE_PROVIDER_CODEX_SESSIONS_PATH=/path/to/.codex/sessions \
scripts/release-provider-live-e2e-lanes.sh run codex

CTX_LIVE_PROVIDER_E2E=1 \
CTX_LIVE_PROVIDER_ACCEPT_LOCAL_HISTORY=1 \
CTX_LIVE_PROVIDER_PI=1 \
CTX_LIVE_PROVIDER_PI_SESSIONS_PATH=/path/to/.pi/sessions.jsonl \
scripts/release-provider-live-e2e-lanes.sh run pi
```

The resulting `live-e2e.json` and `live-e2e.md` contain aggregate counts and
booleans only. They must not include raw transcripts, snippets, queries, or
source paths. Fixture-only providers produce blocked artifacts instead of
passing live proof.

Bazel provider-live targets skip the `ctx` build when the lane is skipped or
only writes fixture-only blocker artifacts. When a real Codex or Pi local-history
run is selected, the wrapper may build or use `ctx`, but the lane runtime still
uses only `ctx` commands with provider API keys and provider CLI environments
left out.

## Import Rules

Provider imports should be:

- read-only with respect to provider-owned files;
- explicit through `ctx import`;
- safe to interrupt and re-run, using idempotent rescans or provider cursors
  when available;
- idempotent for unchanged source files;
- clear about which fields were indexed and which were left raw-only;
- conservative when a transcript schema is unknown or malformed.

## Fidelity

An imported session may include messages, tool calls, command events, output
previews, file references, parent/child agent relationships, usage metadata, and
lifecycle events. Not every provider exposes every field.

Search and context output must identify the provider and cite the source path or
cursor when available so an agent can verify important details.

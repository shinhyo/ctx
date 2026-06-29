# Testing Taxonomy

Public verification focuses on fast local confidence for the search CLI.

## Modes

| Mode | Purpose |
| --- | --- |
| `fast` | Formatting, type checking, public docs checks, CLI help contracts, package-surface audit. |
| `smoke` | `fast` plus a fresh-home CLI flow and basic provider fixture smoke. |
| `presubmit` | `smoke` plus clippy, workspace tests, redaction, and deterministic search checks. |
| `ci` | Buildkite gate: `presubmit` plus the release/content package audit. |
| `perf` | Synthetic CLI/search/import performance budget gates. |

## Commands

```bash
bash scripts/check.sh --mode=fast
bash scripts/check.sh --mode=smoke
bash scripts/check.sh --mode=presubmit
bash scripts/check.sh --mode=ci
bash scripts/check.sh --mode=perf
```

Use direct Bazel targets when a narrower check is enough:

```bash
bazel test //:docs_check
bazel test //:fresh_home_e2e
bazel test //:provider_fixture_e2e
bazel test //:package_audit_release
```

Manual performance gates record JSON evidence under `target/ctx-artifacts` and
are excluded from default suites:

```bash
bash scripts/perf-smoke.sh
bash scripts/check.sh --mode=perf
bazel test //:perf_smoke --config=ci
bazel test //:codex_incremental_import_perf_bench
CTX_CODEX_INCREMENTAL_PERF_SLOW=1 bazel test //:codex_incremental_import_perf_bench
```

`scripts/perf-smoke.sh` is the practical CLI budget harness. It builds
`target/debug/ctx` unless `CTX_PERF_SMOKE_BIN` points at an existing binary,
generates a deterministic Codex session tree under `target/ctx-perf-smoke`,
sets isolated `HOME` and `CTX_DATA_ROOT` values, and writes JSON evidence to
`target/ctx-artifacts/perf-smoke/ctx-cli-perf-smoke.json`.

The default corpus has 2,000 Codex session files and the timed samples run five
times. The harness enforces these p95 budgets by default:

| Profile | Default budget |
| --- | ---: |
| `ctx status --json` | 750 ms |
| `ctx search perfneedle --refresh off --json --limit 20` | 2,500 ms |
| no-op `ctx import --provider codex --path <corpus> --json` | 2,500 ms |
| changed-file incremental import, five files per sample | 3,000 ms |
| `ctx show session <id> --mode lite --format json` | 1,500 ms |

Tune the harness for a slower or noisier worker with environment variables:

```bash
CTX_PERF_SMOKE_SESSIONS=4000 \
CTX_PERF_SMOKE_SEARCH_P95_MS=4000 \
CTX_PERF_SMOKE_IMPORT_NOOP_P95_MS=4000 \
bash scripts/perf-smoke.sh
```

Set `CTX_PERF_SMOKE_ENFORCE=0` to collect evidence without failing the process.
For Buildkite, set `CTX_PUBLIC_CLI_PERF_GATES=1` to run the opt-in public perf
budget step. It executes `bash scripts/check.sh --mode=perf` and collects Bazel
logs plus undeclared test outputs, including the perf smoke JSON artifact. Keep
this mode out of the default public gate unless the worker class has stable
enough CPU and disk behavior for fixed thresholds.

The Codex incremental import perf gate verifies that a large no-op refresh uses
catalog metadata cache hits, parses zero unchanged transcript bodies, imports
zero events, and stays under the configured no-op latency thresholds.

All default public tests must be hermetic. They must not require API keys,
network access, provider accounts, hidden model calls, or writes into source
repositories.

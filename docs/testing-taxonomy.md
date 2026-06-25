# Testing Taxonomy

Public verification focuses on fast local confidence for the search CLI.

## Modes

| Mode | Purpose |
| --- | --- |
| `fast` | Formatting, type checking, public docs checks, CLI help contracts, package-surface audit. |
| `smoke` | `fast` plus a fresh-home CLI flow and basic provider fixture smoke. |
| `presubmit` | `smoke` plus clippy, workspace tests, redaction, and deterministic search checks. |
| `ci` | Buildkite gate: `presubmit` plus the release/content package audit. |

## Commands

```bash
bash scripts/check.sh --mode=fast
bash scripts/check.sh --mode=smoke
bash scripts/check.sh --mode=presubmit
bash scripts/check.sh --mode=ci
```

Use direct Bazel targets when a narrower check is enough:

```bash
bazel test //:docs_check
bazel test //:fresh_home_e2e
bazel test //:provider_fixture_e2e
bazel test //:package_audit_release
```

All default public tests must be hermetic. They must not require API keys,
network access, provider accounts, hidden model calls, or writes into source
repositories.

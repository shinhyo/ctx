# Security Checks

This page defines the checks public docs and production validation should keep
true for the search-only product.

## Required Invariants

- `ctx setup` creates only the configured ctx data root and local storage files.
- `ctx sources` writes nothing.
- `ctx import` writes only the configured ctx data root and SQLite index.
- `ctx search`, `ctx context`, `ctx list`, and `ctx show` write nothing.
- Core setup/import/search/context do not require network access or API keys.
- Provider files are read as sources and not modified.
- Provider transcript imports reject symlinked JSONL files by default.
- JSON output is private by default and must not be described as share-safe.
- Search/context/show JSON and SQLite search projections must not expose
  secret-shaped values that the redaction oracle covers.
- Unsupported providers remain explicit in the provider support matrix.

## Static Docs Checks

Public docs should avoid claims for capabilities outside the product contract.
Run the repository docs check, which scans public copy for removed or unsupported
product surfaces:

```bash
bash scripts/check-docs.sh
```

Validate the provider matrix JSON:

```bash
jq empty docs/provider-support-matrix.json
```

When Bazel owns the docs gate, run:

```bash
bazel test //:docs_check --config=ci
```

## Bazel Security Gates

Run the production security/privacy gates through Bazel:

```bash
bazel test //:security_static_audit //:security_no_repo_writes //:privacy_redaction_oracle --config=ci
```

`//:security_static_audit` scans active runtime crates for hidden
network/client, subprocess, browser, daemon, LLM/API-key, and PATH mutation
surfaces, and checks public setup/docs/install surfaces for PATH edits or API-key
requirements. `//:privacy_redaction_oracle` imports a synthetic provider
history with fake secret-shaped values, then checks `search`, `context`, `show`,
and SQLite search projections for redaction.

## Mode Placement

Security-sensitive product changes should run the `production` mode described in
[`docs/testing-taxonomy.md`](testing-taxonomy.md). Release metadata or
certificate changes should add `release_contract`, which proves fixture and
schema contracts but not real artifacts. Real release artifacts require the
stronger `release` mode.

`provider_live` is an explicit manual opt-in for local-history import proof. It
must not run provider CLIs, require API keys, send product network requests, or
write raw transcript content into artifacts. It is not part of the default
production or release-contract gate.

The default product boundary remains local search only. Security docs and tests
should continue to reject claims that setup, import, search, context, doctor, or
validate need remote accounts, background processes, repository mutation, or API
keys.

## Manual Review Checklist

- README scope matches `docs/product-contract.md`.
- CLI examples use flags implemented by `crates/ctx-cli`.
- Provider support docs match `docs/provider-support-matrix.json`.
- Testing taxonomy keeps manual, provider-live, platform, performance, and
  nightly work out of default production unless explicitly selected.
- JSON docs identify local/private output and compatibility limits.
- Symlink policy stays explicit: provider transcript symlinks are rejected unless
  a future change adds canonical root-contained symlink support with tests.
- Security docs do not promise sanitization beyond bounded previews and
  share-safety markers.
- Release install docs do not imply public artifacts before they exist.

# ctx Search Production Hardening Plan

## Purpose

Move ctx from a locally usable search MVP to a production-ready local agent
history search CLI.

The production product remains intentionally narrow:

> ctx indexes existing local agent transcripts so future agents can search prior
> sessions and retrieve deterministic context with citations.

This plan hardens the product around that boundary. It does not reintroduce a
dashboard, shims, PR evidence, hosted sync, ADE, or hidden LLM summarization.

## Branch And Workspace

- Repo: `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/search-production-hardening`
- Branch: `ctx/search-production-hardening`
- Base: `origin/ctx/search-mvp` at `77722c5`
- Remote target: `origin/ctx/search-production-hardening`

Use only the manual ctx worktree above. Do not use the parent orchestration repo
as a monorepo, and do not push to `main`.

## Non-Negotiable Product Boundary

The shipped default binary, release path, public docs, CLI help, examples,
agent skill, and JSON contracts must expose only local search and deterministic
context retrieval.

Forbidden public/default surfaces:

- dashboard, browser auto-open, daemon, dashboard assets, dashboard docs;
- git/gh/jj shims, PATH edits, shell hook setup, repo hooks;
- PR/evidence/publish/link-pr/gh integration;
- hosted sync, teams, ADE, remote services;
- hidden LLM calls, API-key requirements, network calls in setup/import/search/context;
- public JSON centered on `work_record` or PR/evidence concepts.

Internal compatibility names may survive only when removing them creates more
risk than value, but production gates must prove they are not public, packaged,
or on the default runtime path.

## Bazel-First Policy

Bazel is the production entrypoint. Every production check must be represented
as a Bazel target or Bazel-owned test suite.

Allowed direct commands during implementation:

- read-only inspection commands such as `rg`, `sed`, `git status`, `git diff`;
- file editing and git commands;
- one-time system/tool bootstrap such as installing Bazelisk;
- tightly scoped commands needed to debug a Bazel target, followed by the
  corresponding Bazel target before commit.

Required production commands:

```bash
bazel query //...
bazel test //:presubmit --config=ci
bazel test //:production_hardening --config=ci
bazel test //:release_candidate --config=ci
bazel test //... --config=ci --test_tag_filters=-manual,-external
```

`scripts/check.sh` must become a Bazel launcher. Buildkite must run Bazel, not
Cargo or ad hoc scripts directly.

## Research Completed

Planning used six read-only subagents:

- Architecture/product reviewer: found stale `SECURITY.md`, dormant legacy
  crates, old `.ctx` plan leakage, public JSON `record_id`/`work_record_id`
  leakage, and default legacy layout migration risk.
- Bazel/SDLC reviewer: found `bazel test //...` failed without `HOME`, and
  current Bazel coverage was a single Cargo wrapper.
- Provider E2E reviewer: found Codex is the only strong CLI E2E path, Pi lacks
  CLI E2E, long-tail providers are fixture-only, `--resume` is reporting-only,
  and parent-child edge creation is order-sensitive.
- Security/privacy reviewer: found stale security docs, uneven redaction for
  `show --json`, symlink policy inconsistency, and missing no-network/no-PATH/no
  repo-write gates.
- Docs/fresh-agent reviewer: found docs generally explain the thesis, but JSON,
  lifecycle, provider matrix, first-10-minutes, and agent-skill failure paths
  need concrete contracts and Bazel gates.
- Performance reviewer: found missing deterministic FTS/ranking tie-breakers,
  no synthetic corpus/perf targets, and no scale thresholds or artifact schema.

## Implementation Phases

### Phase 1: Bazel Becomes The Gate

Goal: no production validation depends on direct Cargo/script execution.

Implementation:

- Add a shared Bazel shell runner that:
  - sets `HOME`, `TMPDIR`, `CARGO_HOME`, `RUSTUP_HOME`, `CARGO_TARGET_DIR`;
  - writes artifacts under `$TEST_UNDECLARED_OUTPUTS_DIR/ctx-artifacts`;
  - enforces `--locked` by default;
  - caps local jobs and test threads;
  - supports command-specific wrappers without duplicating environment logic.
- Expand `.bazelrc` with `--config=ci`, test env propagation, resource config,
  and artifact-friendly output.
- Replace the single `//:cargo_tests` surface with targets:
  - `//:cargo_fmt_check`
  - `//:cargo_check`
  - `//:cargo_clippy`
  - `//:cargo_test_default`
  - `//:cargo_test_all_features`
  - `//:docs_check`
  - `//:buildkite_pipeline_check`
  - `//:package_audit_fast`
  - `//:package_audit_release`
  - `//:fresh_home_e2e`
  - `//:provider_fixture_e2e`
  - `//:security_static_audit`
  - `//:security_no_repo_writes`
  - `//:privacy_redaction_oracle`
  - `//:search_determinism_tests`
  - `//:synthetic_search_smoke`
  - `//:release_dry_run_host`
  - `//:release_platform_blocker_freebsd`
  - `//:provider_live_e2e_lane_definitions`
  - `//:release_candidate_metadata_contract`
  - `//:r2_staging_smoke_contract`
  - `//:completion_certificate_contract`
- Add suites:
  - `//:presubmit`
  - `//:production_hardening`
  - `//:release_candidate`
  - `//:manual_external`
- Rewrite `scripts/check.sh` to find/bootstrap Bazel and run the Bazel suites.
- Rewrite `.buildkite/pipeline.yml` to call Bazel only.

Validation:

```bash
bazel query //...
bazel test //:presubmit --config=ci
```

Commit: `Bazelize production validation gates`

### Phase 2: Public Product And Docs Truth

Goal: a fresh agent or human can understand and safely use ctx from the README
and docs without hidden prior context.

Implementation:

- Rewrite `SECURITY.md` around the local search-only product.
- Add or update:
  - `docs/product-contract.md`
  - `docs/first-10-minutes.md`
  - `docs/contracts/json.md`
  - `docs/limitations.md`
  - `docs/security-checks.md`
  - `docs/production-readiness.md`
- Tighten `README.md`, `docs/getting-started.md`, `docs/cli-reference.md`,
  `docs/search.md`, `docs/storage.md`, `docs/provider-support.md`,
  `docs/providers.md`, `docs/threat-model.md`, `docs/release-install.md`, and
  `skills/ctx-agent-memory/SKILL.md`.
- Expand `docs/provider-support-matrix.json` to include all major providers
  with truthful statuses:
  - Codex: local import supported;
  - Pi: local import supported when local Pi history exists;
  - Claude, OpenCode, Antigravity, Gemini, Cursor: fixture contract or
    unsupported/native-blocked until a native importer exists.
- Document exact read/write behavior for every public command.
- Document that JSON contracts are local/private unless explicitly redacted.

Validation:

```bash
bazel test //:docs_check //:provider_support_docs_tests --config=ci
```

Commit: `Document production search contracts`

### Phase 3: Remove Or Quarantine Legacy Public Surface

Goal: Work Recorder, dashboard, PR evidence, publish, report, and VCS/shim
code cannot leak into default production package, docs, or JSON.

Implementation:

- Delete or quarantine dormant tracked crates not in the default search product:
  - `crates/work-record-publish`
  - `crates/work-record-report`
  - `crates/work-record-vcs`
- Delete or quarantine tracked old `.ctx/exec-plans/work-recorder-*` plans from
  release/package-visible source if they remain source-distribution inputs.
- Strengthen package/content audits to fail on:
  - dashboard assets/docs/code in release path;
  - PR/publish/evidence/gh integration in default binary/release path;
  - Work Recorder public docs/help/JSON;
  - old `.ctx` execution plans in production source packages.
- Rename public release artifact paths from `ctx/records` or
  `ctx-records-*` to search/product-neutral names where release scripts expose
  them publicly.

Validation:

```bash
bazel test //:package_audit_fast //:package_audit_release --config=ci
```

Commit: `Quarantine legacy non-search surfaces`

### Phase 4: Public JSON And CLI Contract Hardening

Goal: public JSON is useful for agents and does not center old internal model
names.

Implementation:

- Introduce CLI-facing DTOs for `list`, `show`, `search`, and `context`.
- Prefer public names:
  - `item_id` over `record_id`;
  - `item_type` over `kind: record`;
  - `source_id`/`source_path` over Work Record model names;
  - no top-level public `work_record_id`.
- Stop serializing raw core `Event`/`Session` structs from `ctx show --json`;
  expose stable, documented search-domain fields instead.
- Keep backward-incompatible changes contained to this pre-release hardening
  branch and update tests/docs together.
- Add golden JSON/schema checks for every `--json` command.

Validation:

```bash
bazel test //:cargo_test_default //:json_contract_tests --config=ci
```

Commit: `Harden public JSON contracts`

### Phase 5: Provider E2E And Import Correctness

Goal: provider support is truthfully documented and covered across fixtures,
CLI flows, malformed inputs, idempotency, resume semantics, and raw-source
availability.

Implementation:

- Add provider fixture and CLI E2E tests for:
  - Codex repeat import and `--resume`;
  - Pi import/search/context;
  - malformed provider files with honest failure/progress output;
  - moved/deleted raw source citations;
  - primary/subagent filters;
  - normalized fixture idempotency across Claude, OpenCode, Antigravity,
    Gemini, and Cursor.
- Add out-of-order subagent fixture and fix parent-child edge creation by
  deferring edge insertion until all sessions in a batch are known.
- Clarify `--resume`: either implement real checkpoint resume or document and
  test it as idempotent rescan.
- Add generated large-session tests without committing large files.

Validation:

```bash
bazel test //:provider_fixture_e2e //:provider_cli_e2e_tests --config=ci
```

Commit: `Expand provider import E2E coverage`

### Phase 6: Search Correctness, Determinism, And Performance

Goal: identical inputs produce stable retrieval, and performance regressions are
detectable without flaky presubmit wall-clock failures.

Implementation:

- Add deterministic tie-breakers:
  - SQLite FTS ordering includes stable ID tie-breaks;
  - in-process ranking includes stable ID tie-breaks.
- Add tests for:
  - repeated identical query packets after removing `generated_at`;
  - reverse/random insertion order;
  - DB reopen and search-index refresh;
  - equal score/title/timestamp ties;
  - token budget boundaries and truncation reason.
- Add deterministic synthetic corpus generator with smoke, medium, and perf
  profiles.
- Add performance artifact schema reporting import time, events/sec, DB size,
  search/context timings, result counts, citation counts, and truncation.
- Gate smoke in presubmit; put medium/perf under tagged Bazel suites.

Validation:

```bash
bazel test //:search_determinism_tests //:synthetic_search_smoke --config=ci
bazel test //:search_perf_bench --config=ci --test_tag_filters=perf,manual
```

Commit: `Add deterministic search and scale gates`

### Phase 7: Security And Privacy Hardening

Goal: production checks prove local-only behavior, controlled filesystem
effects, no hidden network/LLM/subprocess surfaces, and documented redaction
limits.

Implementation:

- Add Bazel targets for:
  - no hidden network/LLM/process APIs in default runtime crates;
  - no PATH mutation in CLI/setup/docs;
  - no repo writes during setup/import/search/context;
  - symlink/path traversal probes;
  - privacy redaction oracle across `search`, `context`, `show`, and SQLite FTS.
- Resolve symlink policy for provider imports:
  - reject symlinked transcript files by default, or
  - explicitly allow only canonical root-contained symlinks with tests.
- Decide and document whether `show --json` is private/raw or redacted; test the
  chosen behavior.
- Strengthen release content audit for dependency graph, binary strings,
  manifests, installer metadata, checksums, and package allowlists.

Validation:

```bash
bazel test //:security_static_audit //:security_no_repo_writes //:privacy_redaction_oracle --config=ci
```

Commit: `Add security and privacy gates`

### Phase 8: Release And SDLC Readiness

Goal: production release posture is explicit, repeatable, and Bazel-owned.

Implementation:

- Add release checklist and PR checklist requiring:
  - Bazel suites;
  - product surface audit;
  - provider matrix update;
  - docs contract update;
  - security/privacy checks;
  - performance artifact review when search/import changes.
- Bazelize release dry-run, release candidate metadata, R2 staging smoke,
  FreeBSD blocker, provider live E2E lane definitions, and completion
  certificate contract.
- Keep external/manual blockers explicit:
  - real R2 upload/public HTTPS smoke;
  - signing/notarization;
  - SBOM/provenance;
  - native FreeBSD release lane;
  - live provider E2E requiring real local provider histories.
- Update Buildkite artifact paths for Bazel undeclared outputs.

Validation:

```bash
bazel test //:release_candidate --config=ci
```

Commit: `Bazelize release readiness gates`

## Subagent Implementation Plan

After this plan lands, spawn parallel workers with disjoint ownership:

1. Bazel/CI worker
   - owns `BUILD.bazel`, `.bazelrc`, `scripts/bazel-*.sh`, `scripts/check.sh`,
     `.buildkite/pipeline.yml`;
   - implements Phase 1.
2. Docs/product worker
   - owns README/docs/skill/security docs;
   - implements Phase 2.
3. Legacy/package worker
   - owns dormant crate deletion/quarantine and package audits;
   - implements Phase 3.
4. JSON/CLI worker
   - owns `crates/ctx-cli`, public DTOs, JSON tests;
   - implements Phase 4.
5. Provider worker
   - owns provider fixtures/import tests/import correctness;
   - implements Phase 5.
6. Search/perf worker
   - owns search/store ranking determinism and synthetic perf tests;
   - implements Phase 6.
7. Security worker
   - owns static/security scripts, redaction oracle, no repo-write tests;
   - implements Phase 7.
8. Release/SDLC worker
   - owns release scripts, Buildkite artifacts, PR/release checklist;
   - implements Phase 8.

Workers must be told the codebase is shared and must not revert unrelated edits.
Workers should commit only their owned slice if asked to work in a branch; the
manager integrates, runs Bazel suites, commits, and pushes after each coherent
slice.

## Review Plan

Use separate reviewer subagents after implementation:

- Architecture/product reviewer: no forbidden public surface and coherent
  search-only architecture.
- Bazel/SDLC reviewer: every gate is Bazel-owned and CI uses Bazel only.
- Provider reviewer: matrix/docs/tests match actual importer behavior.
- Security/privacy reviewer: no hidden network/LLM/PATH/repo-write gaps.
- Docs/fresh-agent reviewer: README/docs/skill usable without prior context.
- Performance reviewer: deterministic ranking and perf artifacts are meaningful.
- Final done-criteria agent: compare the final pushed branch against this plan
  line by line and fail if any required item is missing.

## Done Criteria

All must be true before final completion:

- Branch `ctx/search-production-hardening` exists and is pushed.
- Bazel is installed or bootstrapped and `bazel query //...` succeeds.
- `bazel test //... --config=ci --test_tag_filters=-manual,-external` passes.
- `//:presubmit`, `//:production_hardening`, and `//:release_candidate` pass or
  have explicit external/manual blockers documented outside the default gate.
- Buildkite runs Bazel only.
- `scripts/check.sh` runs Bazel only.
- Public CLI help exposes only approved local search commands.
- Removed dashboard/shim/PR/evidence/publish commands are rejected.
- Setup/import/search/context have tests proving no network, no API keys, no
  LLM calls, no PATH edits, no repo writes, no daemon, no browser.
- README/docs/security/skill are search-only and truthful.
- Provider matrix includes all major providers with truthful status and tests.
- JSON contracts are documented and tested.
- `ctx context` remains deterministic retrieval with citations.
- Import semantics are explicit, resumable or honestly idempotent-rescan, and
  safely interruptible.
- Storage defaults to `~/.ctx` and raw provider transcripts are referenced, not
  wholesale duplicated by default.
- Redaction/privacy behavior is documented and tested across search/context/show.
- Search ranking has deterministic tie-breakers and regression tests.
- Synthetic performance smoke target passes and perf/manual target emits
  artifacts.
- Package/content audit proves default binary/release path excludes dashboard
  assets, shims, PR publish/evidence code, gh integration, and stale
  Work Recorder public artifacts.
- Fresh-home E2E passes through Bazel:
  `setup -> sources -> import -> list -> search -> show -> context -> status -> doctor -> validate`.
- Final done-criteria agent signs off.

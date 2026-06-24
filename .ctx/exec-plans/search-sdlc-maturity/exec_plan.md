# ctx Search SDLC Maturity Plan

## Purpose

Raise the search-only ctx CLI from a hardened MVP gate to a production SDLC
shape that is explicit, agent-native, and truthful.

The product boundary does not change:

> ctx indexes existing local agent transcripts so future agents can search prior
> sessions and retrieve deterministic context with citations.

This phase does not reintroduce dashboard, shims, PR/evidence/publish, hosted
sync, hidden LLM calls, or provider execution. Live provider validation means
opt-in local-history import proof only.

## Branch And Workspace

- Repo: `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/search-sdlc-maturity`
- Branch: `ctx/search-sdlc-maturity`
- Base: `origin/ctx/search-production-hardening` at
  `6f8806f6024501f0b1067a04f4996922eb31f844`
- Remote target: `origin/ctx/search-sdlc-maturity`

Use only this manual ctx worktree for this phase. The earlier
`search-production-hardening` worktree contains unrelated in-progress local
changes and must not be edited for this work.

## Baseline Research

Read-only planning used four subagents:

- Test taxonomy reviewer: recommended a small ctx-private-style taxonomy with
  `fast`, `presubmit`, `production`, `release_contract`, `release`, `nightly`,
  `perf`, `provider_live`, `platform`, and compatibility aliases.
- Release/Buildkite reviewer: found the current release candidate targets are
  contract proof, not real multi-platform artifact proof; recommended keeping
  required Buildkite passable while adding truthful manual/future release proof
  lanes and a real certificate self-test.
- Live provider reviewer: found old Work Recorder live E2E was not revivable as
  a real runner; recommended Codex and Pi only, local-history import only, with
  explicit opt-in, no API keys, no provider execution, and redacted artifacts.
- Adversarial reviewer: flagged scope creep, false release confidence,
  completion certificate drift, static-only side-effect checks, and provider
  support overstatement.

The pre-split private monorepo baseline was
`a9dce1c6d59d1a43b0f4b86259787bc78ab458bc`. It had richer Buildkite
orchestration, BuildBuddy cache/RBE, a test taxonomy registry, provider
matrices, and release proof. This public repo should adopt the useful shape
without importing the old product scope or RBE complexity.

## Non-Negotiable Product Boundary

Default CI and public docs must keep these true:

- Public CLI/help/docs expose only setup, status, sources, import, list, show,
  search, context, doctor, validate.
- No dashboard, daemon, browser auto-open, shims, shell hooks, PATH edits,
  repo hooks, PR/evidence/publish, hosted sync, or ADE surfaces.
- setup/import/search/context require no API keys and make no product network
  calls.
- setup writes only ctx storage; import writes only ctx storage; sources/list/
  show/search/context/doctor/validate do not mutate repositories or provider
  histories.
- Live provider E2E is manual/external, local-history import proof only.
- Fixture-only providers must not be documented as live-supported.
- Release gates must distinguish contract fixtures from real platform
  artifacts and from public publishing.

## Phase 1: Explicit Bazel Test Taxonomy

Goal: agents and Buildkite can choose the right verification tier without
guessing from target names.

Implementation:

- Add Bazel suites:
  - `//:fast`
  - `//:presubmit`
  - `//:production`
  - `//:release_contract`
  - `//:release`
  - `//:platform`
  - `//:perf`
  - `//:provider_live`
  - `//:nightly`
  - `//:manual`
- Keep compatibility aliases:
  - `//:production_hardening` -> `//:production`
  - `//:release_candidate` -> `//:release_contract`
  - `//:manual_external` -> `//:manual`
- Keep legacy broad-feature coverage discoverable outside current production
  taxonomy:
  - `//:legacy_all_features`
  - `//:legacy`
- Add a `//:cli_contract_tests` leaf for public CLI command/help/provider
  contract tests currently hidden inside the security static audit.
- Tag leaves and manual targets enough that wildcard runs can exclude manual,
  external, provider-live, and perf lanes.
- Keep `//:manual` scoped to current search-only manual lanes: perf,
  provider-live, and manual external contract. Do not include legacy
  all-features evidence/pull-request tests in `//:manual`.
- Update `scripts/check.sh` to support:
  - `--mode=fast`
  - `--mode=ci`
  - `--mode=presubmit`
  - `--mode=production`
  - `--mode=release-contract`
  - `--mode=release`
  - `--mode=nightly`
  - `--mode=platform`
  - `--mode=provider-live`
  - `--mode=perf`
  - `--mode=manual`
  - `--list-modes`
  - `-- <bazel args...>` passthrough
- Make Buildkite call an explicit mode instead of relying on default.
  The required Buildkite gate uses `--mode=ci`, which runs release-contract
  coverage plus wildcard non-manual target detection.

Validation:

```bash
bazel query //...
./scripts/check.sh --list-modes
./scripts/check.sh --mode=fast
./scripts/check.sh --mode=ci
./scripts/check.sh --mode=production
bazel test //:release_contract --config=ci
```

## Phase 2: Docs And Agent-Native SDLC Contract

Goal: a fresh agent can answer which checks to run, when to escalate, and which
results are release proof.

Implementation:

- Add `docs/testing-taxonomy.md`.
- Update:
  - `README.md`
  - `docs/production-readiness.md`
  - `docs/security-checks.md`
  - `docs/provider-support.md`
  - `docs/providers.md`
  - `docs/contracts/json.md`
  - `docs/release-install.md`
  - `scripts/check-docs.sh`
- Add or complete release documentation required by the certificate:
  - `docs/release-supply-chain.md`
  - `docs/release-r2-layout.md`
  - `docs/freebsd-release-worker.md`
- Document remote-cache posture:
  - no RBE in this phase;
  - no remote cache by default;
  - reconsider cache-only if Buildkite p50 exceeds 12 minutes, p95 exceeds 20
    minutes for two weeks, or multi-platform release proof exceeds 25 minutes
    with repeated cacheable work.

Validation:

```bash
bazel test //:docs_check --config=ci
```

## Phase 3: Safe Live Provider E2E

Goal: revive only the useful part of live provider validation: opt-in proof that
ctx can import real local histories and retrieve search/context from them.

Implementation:

- Extend `scripts/release-provider-live-e2e-lanes.sh` so:
  - `definitions` keeps non-publishing lane definitions;
  - `run codex` and `run pi` can run real local-history smoke when explicitly
    opted in;
  - fixture-only providers remain blockers;
  - `run-selected` can run selected local providers or skip truthfully.
- Env contract:
  - `CTX_LIVE_PROVIDER_E2E=1`
  - `CTX_LIVE_PROVIDER_ACCEPT_LOCAL_HISTORY=1`
  - `CTX_LIVE_PROVIDER_CODEX=1`
  - `CTX_LIVE_PROVIDER_PI=1`
  - `CTX_LIVE_PROVIDER_CODEX_SESSIONS_PATH`
  - optional `CTX_LIVE_PROVIDER_CODEX_HISTORY_PATH`
  - `CTX_LIVE_PROVIDER_PI_SESSIONS_PATH`
  - optional provider-specific query env vars
- Add Bazel manual targets:
  - `//:provider_live_e2e_codex`
  - `//:provider_live_e2e_pi`
  - `//:provider_live_e2e_selected`
- Artifacts:
  - `live-e2e.json`
  - `live-e2e.md`
  - redacted aggregate counts only;
  - no raw transcripts, snippets, queries, API keys, or raw source paths.
- Guardrails:
  - unset API-key env vars while invoking ctx;
  - do not execute provider CLIs;
  - use temp `CTX_DATA_ROOT`;
  - never add live provider lanes to default production or release contract
    suites.

Validation:

```bash
bazel test //:provider_live_e2e_selected --config=ci --test_tag_filters=manual,external
bazel test //:manual --config=ci --test_tag_filters=manual
```

The default path should skip when no live provider env is set. Real provider
runs require explicit local paths.

## Phase 4: Release Contract And Certificate Truthfulness

Goal: release tests are honest about fixture contracts versus real artifact
proof, and the completion certificate is actually runnable against produced
contract evidence.

Implementation:

- Add `//:release_contract` as the current non-publishing fixture/schema suite.
- Keep `//:release_candidate` as an alias to avoid breaking existing callers.
- Improve `completion_certificate_contract` to create a fixture evidence tree,
  run `scripts/release-completion-certificate.sh` against it in explicit
  self-test mode, and fail on missing evidence/docs.
- Add evidence fields where practical:
  - `evidence_class`
  - `self_test_fixture`
  - Buildkite metadata when available
  - `publishing:false`
- Add Buildkite comments/conditionals for future manual release proof lanes
  without making unsupported macOS/Windows/FreeBSD queues required.

Validation:

```bash
bazel test //:completion_certificate_contract --config=ci
bazel test //:release_contract --config=ci
```

## Phase 5: Runtime Side-Effect And Network Oracles

Goal: catch regressions that static greps miss.

Implementation:

- Strengthen the existing no-repo-write gate with a filesystem side-effect
  oracle:
  - temp HOME with fake `.bashrc`, `.zshrc`, and repo hooks;
  - read-only provider fixtures;
  - hashes before/after;
  - assert setup/import/search/context do not modify shell files, repo files,
    provider sources, or hooks.
- Add a no-network runtime oracle when the host has `strace`; otherwise write a
  skipped artifact that states the missing tool. This is evidence, not a hard
  portability blocker.
- Keep static audits for forbidden crates and APIs.

Validation:

```bash
bazel test //:security_no_repo_writes //:security_static_audit --config=ci
```

## Phase 6: Buildkite And Remote Branch

Goal: branch is pushed, Buildkite runs the CI gate, and manual lanes are
documented but not default-required.

Implementation:

- Update `.buildkite/pipeline.yml`:
  - required Linux step runs `./scripts/check.sh --mode=ci`;
  - artifact paths include Bazel undeclared outputs;
  - optional/manual live provider and release proof comments or conditional
    steps do not run by default.
- Push `ctx/search-sdlc-maturity`.
- Verify Buildkite for the branch. If Buildkite cannot be triggered from this
  environment, record the exact blocker and local equivalent commands.

Validation:

```bash
bazel test //:buildkite_pipeline_check --config=ci
git ls-remote --heads origin ctx/search-sdlc-maturity
```

## Worker Split

Implementation workers:

1. Taxonomy/docs worker
   - owns docs taxonomy and docs check updates;
   - may not edit `BUILD.bazel`, `scripts/check.sh`, or `scripts/bazel-test.sh`.
2. Live provider worker
   - owns `scripts/release-provider-live-e2e-lanes.sh` and provider docs;
   - may not edit `BUILD.bazel`, `scripts/check.sh`, or `scripts/bazel-test.sh`.
3. Release/certificate worker
   - owns release docs and `scripts/release-completion-certificate.sh`;
   - may not edit `BUILD.bazel`, `scripts/check.sh`, or `scripts/bazel-test.sh`.
4. Main integrator
   - owns Bazel suites, check modes, Buildkite, `scripts/bazel-test.sh`,
     validation, commits, push, and Buildkite follow-through.

Review workers:

1. Architecture/product reviewer
   - fail if product boundaries regress or public surfaces overstate support.
2. SDLC/release reviewer
   - fail if taxonomy, Buildkite, release proof, or certificate gates are
     misleading.
3. Live-provider/security reviewer
   - fail if live provider lanes leak raw content, require API keys, run
     provider CLIs, or enter default CI.
4. Final done-certifier
   - compare final branch to this plan line by line.

## Final Done Criteria

- Branch exists and is pushed to `origin/ctx/search-sdlc-maturity`.
- `scripts/check.sh` supports documented modes and remains Bazel-first.
- Required Buildkite step uses `./scripts/check.sh --mode=ci`.
- Bazel suites exist and aliases preserve old target names.
- Manual provider-live targets exist but are excluded from default production
  and release-contract runs.
- Legacy all-features tests remain discoverable through `//:legacy_all_features`
  and `//:legacy`, but are not part of `//:manual`.
- Codex/Pi live E2E can run from explicit local history paths and writes only
  redacted aggregate artifacts.
- Fixture-only providers remain fixture-only in docs and matrix.
- Completion certificate contract runs against generated evidence, not grep
  only.
- FreeBSD x64 remains a first-class release target; release evidence must
  include `freebsd-x64` proof or an explicit blocker/exception artifact until a
  native FreeBSD worker exists.
- Docs explain taxonomy, release contract versus real artifact proof, provider
  live E2E, and remote-cache posture.
- No RBE or default remote cache is introduced.
- Public CLI/help/docs remain search-only.
- Local validation passes:
  - `bazel query //...`
  - `./scripts/check.sh --mode=fast`
  - `./scripts/check.sh --mode=ci`
  - `./scripts/check.sh --mode=production`
  - `bazel test //:release_contract --config=ci`
  - `bazel test //:manual --config=ci --test_tag_filters=manual`
  - `bazel test //... --config=ci --test_tag_filters=-manual,-external,-provider-live,-perf`
- Review agents sign off.
- Buildkite CI gate passes, or an explicit external CI trigger blocker
  is documented with all local equivalents passing.

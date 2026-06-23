# Work Recorder Productization Validation Log

Updated: 2026-06-22T19:53:06-05:00

## 2026-06-22 Baseline Public Branch Check

- Command: `./scripts/check.sh`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head at start: `work-record` / `4c60fe8`
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets`;
  - `cargo test --workspace --all-targets`;
  - 10 CLI integration tests passed;
  - 1 report unit test passed;
  - 4 store unit tests passed.
- Notes: this is the slim public Work Recorder branch, not the prior large ADE
  workspace.

## 2026-06-22 First Integrated Slice Checks

- Command:
  `bash -n scripts/check.sh scripts/bazel-test.sh scripts/release-dry-run.sh scripts/ci-common.sh`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Outcome: PASS
- Notes: verified shell syntax for new resource-safe scripts.

- Command: `git diff --check`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Outcome: PASS

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.
- Notes:
  - `TMPDIR=/var/tmp/ctxwr` avoided the `/tmp` pressure seen in child workers.
  - Test coverage after core-type expansion: 10 CLI integration tests, 2 core
    unit tests, 1 report unit test, and 4 store unit tests passed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 ./scripts/release-dry-run.sh`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Outcome: PASS
- Artifacts:
  - `target/ctx-artifacts/release-dry-run/manifest.json`;
  - `target/ctx-artifacts/release-dry-run/checksums.sha256`;
  - `target/ctx-artifacts/release-dry-run/timings.json`.

## 2026-06-22 Local Product Review Blocker Checks

- Command:
  `mkdir -p /var/tmp/ctxwr && cargo fmt --all && TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p work-record-core -p work-record-store -p work-record-capture -p work-record-search -p work-record-report -p ctx --test cli --offline`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `83611d2`
- Outcome: PASS
- Coverage:
  - 26 CLI integration tests passed, including auto-import, repair, shim, VCS,
    dashboard, search/context, and redaction coverage.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p work-record-core -p work-record-store -p work-record-capture -p work-record-search -p work-record-report --offline`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `83611d2`
- Outcome: PASS
- Coverage:
  - 4 capture unit tests passed, including shim provenance persistence.
  - 5 core unit tests passed, including shared redaction behavior.
  - 2 report unit tests passed, including defensive dashboard redaction.
  - 2 search unit tests passed.
  - 10 store unit tests passed, including artifact-backed evidence, redaction,
    import atomicity, and FTS evidence-only search.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all && ./scripts/check-docs.sh && git diff --check`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `83611d2`
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - 26 CLI integration tests, 4 capture unit tests, 5 core unit tests, 2 report
    unit tests, 2 search unit tests, 10 store unit tests, and 7 VCS unit tests
    passed;
  - docs/product-claim checks passed;
  - `git diff --check` passed;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.

## 2026-06-22 Local Shims And Docs/Examples Checks

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p work-record-capture -p ctx -- --test-threads=1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / `c572a4b`
- Outcome: PASS
- Coverage:
  - 24 CLI integration tests passed, including local shim install/env/uninstall,
    overwrite refusal, real `git` command execution through the shim, and capture
    spool import from shim output.
  - 3 capture unit tests passed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 cargo build -p ctx --bin ctx && ./scripts/check-docs.sh && CTX_BIN=target/debug/ctx CTX_EXAMPLE_TMPDIR=/var/tmp/ctxwr-examples ./examples/local-record-workflow.sh && CTX_BIN=target/debug/ctx CTX_EXAMPLE_TMPDIR=/var/tmp/ctxwr-examples ./examples/capture-spool-fixture.sh && git diff --check`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / `5c710b6`
- Outcome: PASS
- Coverage:
  - built current `ctx` binary;
  - docs/examples syntax and product-claim checks passed;
  - local record workflow created a temporary Work Record, command evidence,
    VCS/PR helper output, PR link, context/report output, static dashboard,
    archive JSON, and validation result;
  - capture spool fixture wrote/imported a fixture envelope and validated
    storage;
  - `git diff --check` passed.
- Artifacts:
  - example dashboard path printed under
    `/var/tmp/ctxwr-examples/ctx-work-record-example.*/dashboard/index.html`;
  - example archive path printed under
    `/var/tmp/ctxwr-examples/ctx-work-record-example.*/work-records.json`.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all && ./scripts/check-docs.sh && git diff --check`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / `5c710b6`
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - 24 CLI integration tests, 3 capture unit tests, 4 core unit tests, 2 report
    unit tests, 2 search unit tests, 9 store unit tests, and 7 VCS unit tests
    passed;
  - `scripts/check-docs.sh` passed;
  - `git diff --check` passed;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.

## 2026-06-22 Capture Auto-Import, Doctor, And Repair Checks

- Command:
  `cargo fmt --all && TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p work-record-capture -p ctx -- --test-threads=1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted auto-import/doctor/repair changes on `be4268e`
- Outcome: PASS
- Coverage:
  - 26 CLI integration tests passed, including normal command auto-import,
    `ctx doctor`, and `ctx repair --json`.
  - 3 capture unit tests passed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all && ./scripts/check-docs.sh && git diff --check`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted auto-import/doctor/repair changes on `be4268e`
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - 26 CLI integration tests, 3 capture unit tests, 4 core unit tests, 2 report
    unit tests, 2 search unit tests, 9 store unit tests, and 7 VCS unit tests
    passed;
  - `scripts/check-docs.sh` passed;
  - `git diff --check` passed;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.

## 2026-06-22 Foundation Re-Review Fix Checks

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p ctx -p work-record-core -p work-record-store -- --test-threads 1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `b7abdca`
- Outcome: PASS after updating the import atomicity test to expect the new
  deterministic preflight `record not found` error instead of a SQLite FK error.
- Coverage:
  - 11 CLI integration tests passed;
  - 4 core unit tests passed;
  - 9 store unit tests passed;
  - core/store doc-tests passed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `b7abdca`
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 ./scripts/release-dry-run.sh && git diff --check`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `b7abdca`
- Outcome: PASS
- Artifacts:
  - `target/ctx-artifacts/release-dry-run/manifest.json`;
  - `target/ctx-artifacts/release-dry-run/checksums.sha256`;
  - `target/ctx-artifacts/release-dry-run/timings.json`.

## 2026-06-22 Archive Payload Fix Checks

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p ctx -p work-record-core -p work-record-store -- --test-threads 1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `77d227f`
- Outcome: PASS
- Coverage:
  - 11 CLI integration tests passed;
  - 4 core unit tests passed;
  - 9 store unit tests passed;
  - core/store doc-tests passed;
  - store archive round-trip now asserts full artifact payload content survives
    export/import while evidence rows expose safe previews.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `77d227f`
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 ./scripts/release-dry-run.sh && git diff --check`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `77d227f`
- Outcome: PASS
- Artifacts:
  - `target/ctx-artifacts/release-dry-run/manifest.json`;
  - `target/ctx-artifacts/release-dry-run/checksums.sha256`;
  - `target/ctx-artifacts/release-dry-run/timings.json`.

## Environment Notes

- Root filesystem has available space; `/tmp` was comparatively full. Use
  `TMPDIR=/var/tmp/ctxwr` or another disk-backed temp root for cargo-heavy work.
- Do not run broad Cargo checks from multiple agents concurrently on this host.
  Use the repo's resource-capped scripts with low job counts and disk-backed
  temp space.

## 2026-06-22 Root CLI And Store Foundation Checks

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p ctx --locked -- --test-threads 1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Outcome: PASS
- Coverage:
  - 11 CLI integration tests passed;
  - root commands covered;
  - hidden `ctx workspace ...` and `ctx work ...` compatibility aliases covered.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - 11 CLI integration tests, 2 core unit tests, 1 report unit test, and 8 store
    unit tests passed;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 ./scripts/release-dry-run.sh`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Outcome: PASS
- Artifacts:
  - `target/ctx-artifacts/release-dry-run/manifest.json`;
  - `target/ctx-artifacts/release-dry-run/checksums.sha256`;
  - `target/ctx-artifacts/release-dry-run/timings.json`.

Future entries must include:

- exact command;
- worktree/repo;
- start/end timestamp;
- outcome;
- failure mode if any;
- whether the command was local, Buildkite, or staging.

## 2026-06-22 Dashboard Export And Visual Checks

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p work-record-report --lib -- --test-threads 1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted dashboard redaction hardening on `a5b63b9`
- Outcome: PASS
- Coverage:
  - 2 report unit tests passed.
  - Dashboard HTML test asserts escaped content, safe workspace labels, no raw
    absolute workspace path, and no raw token-like command fragment.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 cargo build -p ctx --bin ctx`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted dashboard redaction hardening on `a5b63b9`
- Outcome: PASS

- Commands:
  `target/debug/ctx setup`,
  `target/debug/ctx record`,
  `target/debug/ctx evidence run`,
  `target/debug/ctx link-pr`,
  `target/debug/ctx capture write-fixture`,
  `target/debug/ctx capture import --json`,
  `target/debug/ctx dashboard export --output /var/tmp/ctxwr-dashboard`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Data root:
  `/var/tmp/ctxwr-dashboard-data`
- Outcome: PASS
- Artifacts:
  - `/var/tmp/ctxwr-dashboard/index.html`
  - `/var/tmp/ctxwr-dashboard/dashboard.png`
  - `/var/tmp/ctxwr-dashboard/dashboard-mobile.png`
- Notes:
  - Headless Chrome required `/var/tmp` profile/cache/temp flags on this host.
  - Manual screenshot inspection found the desktop and mobile reports populated
    and responsive after redaction hardening.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all && git diff --check`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted dashboard redaction hardening on `a5b63b9`
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - 21 CLI integration tests, 3 capture unit tests, 4 core unit tests, 2 report
    unit tests, 2 search unit tests, 9 store unit tests, and 7 VCS unit tests
    passed;
  - `git diff --check` passed;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.

## 2026-06-22 Capture Spool Integration Checks

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p work-record-capture --lib -- --test-threads 1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / capture merge with uncommitted archive-schema compatibility fix
- Outcome: PASS
- Coverage:
  - 3 capture unit tests passed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p ctx capture -- --test-threads 1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / capture merge with uncommitted archive-schema compatibility fix
- Outcome: PASS
- Coverage:
  - 2 capture CLI integration tests passed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all && git diff --check`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / capture merge with uncommitted archive-schema compatibility fix
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - 13 CLI integration tests, 3 capture unit tests, 4 core unit tests, 1 report
    unit test, and 9 store unit tests passed;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.

## 2026-06-22 VCS And PR Integration Checks

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p work-record-vcs --lib -- --test-threads 1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / VCS merge with uncommitted conflict resolution
- Outcome: PASS
- Coverage:
  - 7 VCS unit tests passed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p ctx --test cli -- --test-threads 1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / VCS merge with uncommitted conflict resolution
- Outcome: PASS
- Coverage:
  - 15 CLI integration tests passed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all && git diff --check`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / VCS merge with uncommitted conflict resolution
- Outcome: PASS
- Notes:
  - First full-check attempt failed on two Clippy `needless_borrow` findings in
    `work-record-vcs`; parser code was fixed and the full check then passed.
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - 15 CLI integration tests, 3 capture unit tests, 4 core unit tests, 1 report
    unit test, 9 store unit tests, and 7 VCS unit tests passed;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.

## 2026-06-22 Search And Context Integration Checks

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p work-record-search --lib -- --test-threads 1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / `e9b5e29`
- Outcome: PASS
- Coverage:
  - 2 search unit tests passed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p ctx --test cli -- --test-threads 1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / `e9b5e29`
- Outcome: PASS
- Coverage:
  - 20 CLI integration tests passed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all && git diff --check`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / `e9b5e29`
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - 20 CLI integration tests, 3 capture unit tests, 4 core unit tests, 1 report
    unit test, 2 search unit tests, 9 store unit tests, and 7 VCS unit tests
    passed;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 ./scripts/release-dry-run.sh`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / `8f0401d`
- Outcome: PASS
- Artifacts:
  - `target/ctx-artifacts/release-dry-run/manifest.json`;
  - `target/ctx-artifacts/release-dry-run/checksums.sha256`;
  - `target/ctx-artifacts/release-dry-run/timings.json`.

## 2026-06-22 Foundation Review Fix Checks

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 cargo test -p ctx -p work-record-core -p work-record-store -- --test-threads 1`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `eb0d8f9`
- Outcome: PASS
- Coverage:
  - 11 CLI integration tests passed;
  - 3 core unit tests passed;
  - 9 store unit tests passed;
  - core/store doc-tests passed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 BAZEL_JOBS=2 ./scripts/check.sh all`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `eb0d8f9`
- Outcome: PASS
- Coverage:
  - `cargo fmt --all -- --check`;
  - `cargo check --workspace --all-targets --locked`;
  - `cargo clippy --workspace --all-targets --locked -- -D warnings`;
  - `cargo test --workspace --all-targets --locked -- --test-threads 1`;
  - Bazel lane recorded `skipped` because neither `bazel` nor `bazelisk` is
    installed.

- Command:
  `TMPDIR=/var/tmp/ctxwr CARGO_BUILD_JOBS=2 RUST_TEST_THREADS=1 ./scripts/release-dry-run.sh`
- Repo/worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/work-record-product`
- Branch/head:
  `work-record` / uncommitted changes on `eb0d8f9`
- Outcome: PASS
- Artifacts:
  - `target/ctx-artifacts/release-dry-run/manifest.json`;
  - `target/ctx-artifacts/release-dry-run/checksums.sha256`;
  - `target/ctx-artifacts/release-dry-run/timings.json`.

# Buildkite Release Verification Status

Updated: 2026-06-21T10:44:00Z

Branch: `ctx/agent-work-semantics-primary`

Buildkite evidence head: `6ae30f8cfb98d759ec1396640b26ed4ac601133d`

Initial status-note commit: `284dde9c9d935a0c5e48afd3d3e9d2c9a109b68a`

Draft PR: https://github.com/ctxrs/ctx/pull/10

Buildkite pipeline: https://buildkite.com/luca-king/ctx-public-release-verification

Final evidence build: https://buildkite.com/luca-king/ctx-public-release-verification/builds/20

## Summary

The Buildkite release verification matrix is implemented and CI-visible. Build
#20 passed every repo/product lane that could run from healthy workers:

- source contracts;
- build graph no-build analysis;
- full Rust Bazel gate;
- full web Bazel gate;
- Linux CLI;
- Windows CLI cross-package and native Windows smoke;
- Linux desktop/Tauri package build;
- browser premerge E2E;
- release proof;
- release artifact build.

The only remaining red lanes are the two macOS desktop package lanes. They fail
before repository checkout and before repo-owned commands run because the shared
macOS Buildkite agents cannot remove stale checkout directories from previous
jobs.

This is an external worker-state blocker, not a product/code/test failure in
this branch.

## Buildkite Matrix

| Lane | Product / Platform | Build #20 status | Evidence |
| --- | --- | --- | --- |
| source: contracts | CI/source contracts | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56b9-4c8b-9317-7b9f8c536a01 |
| build graph: no-build analysis | Bazel graph | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56c1-4fe8-acdb-320842cab1d5 |
| rust: all-rust | Rust workspace | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56c2-4b85-bda1-127211a7ec51 |
| web: all-web | Web app | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56c3-41f7-8002-086b77d0ea83 |
| cli: linux x64 | CLI Linux x64 | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56c4-4202-94bc-b81d8905f6fc |
| cli: windows x64 package | CLI Windows x64 package | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56c5-404c-b372-2b7fed126a17 |
| cli: windows x64 | CLI Windows x64 native smoke | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56c6-40f4-93d3-90157c0aabd9 |
| desktop: package linux x64 | Desktop Linux x64 package | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56ca-4e5c-a8bf-e4114234b41e |
| desktop: package macos arm64 | Desktop macOS arm64 package | blocked | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56cb-49ba-aeca-40ef7a33fabf |
| desktop: package macos x64 | Desktop macOS x64 package | blocked | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56cf-4c39-a9f0-0ccb0f3506ae |
| browser: premerge e2e | Browser E2E | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56d3-4c53-a6fb-0f5ace20b627 |
| release: proof | Release proof | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56d4-4dda-9286-1f540708941f |
| artifact: release | Release artifacts | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/20#019ee9ae-56d5-4d27-896b-cb2617ad70a8 |

## macOS Blocker

Both macOS package lanes fail before checkout completes. The Buildkite agent
tries to remove a stale checkout directory, then repeatedly fails with
permission denied while unlinking:

`core/apps/desktop/src-tauri/web/dist/favicon-16x16.png`

Affected checkout roots observed in the logs:

- `/Users/ctxrunner/.buildkite-agent/builds/ctxrunner-Mac-mini-ctx-mac-gui-shared-arm64/luca-king/ctx-public-release-verification`
- `/usr/local/var/buildkite-agent/builds/ctxcis-iMac-ctx-mac-gui-shared-x64/luca-king/ctx-public-release-verification`

Buildkite docs indicate `BUILDKITE_BUILD_CHECKOUT_PATH` cannot be overridden by
pipeline YAML; it must be set by an agent environment or pre-checkout hook. From
this repo, the safe remediation is therefore not available.

Required infra remediation:

- clean or remove the stale checkout directories on both shared macOS hosts;
- fix ownership/permissions so the Buildkite agent user can unlink generated
  files;
- ideally update the macOS agent pre-checkout/environment hook to use a
  build/job-unique checkout path or to repair stale checkout ownership before
  checkout.

After that remediation, rerun the same Buildkite pipeline on this branch.

## Changes Landed

- Added public Buildkite release-verification coverage for Rust, web, Linux CLI,
  Windows CLI package/smoke, Linux/macOS desktop packaging, browser E2E, release
  proof, and release artifacts.
- Added resource-conscious Bazel defaults for Buildkite.
- Added Linux and Windows CLI verification scripts.
- Added desktop package preparation scripts for Linux and macOS.
- Added a public macOS shared-agent pre-command compatibility hook.
- Scrubbed inherited signing/notarization/updater env from public release
  verification package lanes.
- Added a local Buildkite toolchain helper that avoids privileged `corepack`
  global shims and verifies bootstrapped Node tarballs with pinned SHA256 hashes.
- Fixed Windows CLI cross-build portability issues.
- Fixed sandbox-runtime test isolation issues exposed by the full Rust gate.
- Copied desktop sidecar binaries with both base names and Tauri target-triple
  suffixes.
- Let downstream proof lanes continue after desktop failures so unrelated proof
  evidence is still collected while desktop platform blockers remain visible.

## Artifact Coverage

- Windows CLI package lane uploads `ctx-cli-windows-x64/**/*` and the native
  Windows smoke lane uploads `ctx-cli-windows-x64-smoke.json`.
- Linux desktop package lane uploads
  `core/apps/desktop/src-tauri/target/release/bundle/**/*`; build #20 passed
  after producing Linux desktop bundle artifacts.
- Release artifact lane uploads web dist, Linux CLI, and Bazel testlogs from
  `//:release-artifacts`; build #20 passed.

The artifact-listing helper hit its page cap on build #20 because the build
uploaded many files, so artifact coverage is recorded by lane and configured
artifact paths instead of enumerating every artifact.

## Local Validation

Light local checks run during this pass:

- `.buildkite/validate-pipeline.sh`
- `bash -n` for changed Buildkite shell scripts
- `git diff --check`
- focused local pnpm-resolution smoke for `.buildkite/ci-toolchain.sh`

Broad local Rust/web suites were not rerun in this phase because Buildkite build
#20 passed the full `//:all-rust` and `//:all-web` gates, and the local host has
known I/O pressure under broad concurrent Rust builds.

## Review Status

- CI helper read-only review found no blocker. Its supply-chain concern about
  unverified Node bootstrap downloads was addressed with pinned SHA256
  verification in `.buildkite/ci-toolchain.sh`.
- Final SDLC/security and done-ness reviews are pending against this status
  note and head.

## Guardrails Confirmed

- No merge to `main`.
- No release or public announcement.
- No ctx release publish.
- No secrets intentionally printed by repo-owned scripts; signing/notarization
  env is scrubbed before public package verification commands.
- The draft PR remains draft/open.

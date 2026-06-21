# Buildkite Release Verification Status

Updated: 2026-06-21T12:14:39Z

Branch: `ctx/agent-work-semantics-primary`

Buildkite evidence head: `0d82533a2c63c132b7e715c21f0b95ce6529c74a`

Draft PR: https://github.com/ctxrs/ctx/pull/10

Buildkite pipeline: https://buildkite.com/luca-king/ctx-public-release-verification

Final evidence build: https://buildkite.com/luca-king/ctx-public-release-verification/builds/23

## Summary

Buildkite release verification is green for the required public matrix. Build
#23 passed all 14 command jobs on commit
`0d82533a2c63c132b7e715c21f0b95ce6529c74a`, including both macOS desktop
package lanes that were previously blocked by stale shared-agent checkout
directories.

No ctx merge, release, publish, or announcement was performed.

## Buildkite Matrix

| Lane | Product / Platform | Build #23 status | Evidence |
| --- | --- | --- | --- |
| pipeline upload | Buildkite pipeline parse/upload | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-4b14-48e9-b18a-21f30ee2933e |
| source: contracts | CI/source contracts | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-674c-4874-acad-c9ae71f47cd3 |
| build graph: no-build analysis | Bazel graph | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-6753-4337-bc12-3aa035781f85 |
| rust: all-rust | Rust workspace | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-6755-41fb-b5fc-3f08d443025f |
| web: all-web | Web app | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-6756-4081-8851-22c7d7dd723d |
| cli: linux x64 | CLI Linux x64 | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-6757-4e2d-9fda-2fe37e7cca4f |
| cli: windows x64 package | CLI Windows x64 package | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-6758-440e-8b5f-6a7c46909091 |
| cli: windows x64 | CLI Windows x64 native smoke | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-6758-461a-88d3-7b25f9250953 |
| desktop: package linux x64 | Desktop Linux x64 package | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-675e-4ed5-9bce-0fb55219c499 |
| desktop: package macos arm64 | Desktop macOS arm64 package | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-675f-4c3b-8c53-ca484ff21b99 |
| desktop: package macos x64 | Desktop macOS x64 package | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-6763-4ca3-ab64-d5f54ec576d1 |
| browser: premerge e2e | Browser E2E | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-676a-4e74-9091-fc56fe34d650 |
| release: proof | Release proof | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-676b-4744-8592-5791161b3b48 |
| artifact: release | Release artifacts | passed | https://buildkite.com/luca-king/ctx-public-release-verification/builds/23#019ee9f9-676c-46d4-b3b1-a76f039faf69 |

## macOS Remediation

The earlier macOS blocker was real worker state: the default Buildkite checkout
cleanup could not remove stale shared-agent directories before repo-owned
commands ran. The remediation is now repo-owned pipeline code:

- added `custom-checkout#v1.8.0` to both macOS desktop package lanes;
- configured `skip_checkout: true` so the default shared checkout cleanup path
  is bypassed;
- configured a job-unique checkout root with the build number, step key, and job
  id:
  `$${TMPDIR:-/tmp}/ctx-public-release-verification-$${BUILDKITE_BUILD_NUMBER}-$${BUILDKITE_STEP_KEY}-$${BUILDKITE_JOB_ID}`;
- left signing, notarization, and updater private-key environment scrubbing in
  the package scripts.

Evidence from the remediation sequence:

- Build #21 proved the custom checkout approach could bypass the stale checkout
  directories and let macOS packaging pass, but the checkout path interpolated
  too early.
- Build #22 corrected interpolation so macOS jobs received distinct runtime
  checkout roots. Both macOS package lanes passed, but the artifact upload still
  used only the old `src-tauri/target` bundle path.
- Build #23 added `core/target/release/bundle/**/*` to the desktop artifact
  paths and passed the full matrix.

Infra cleanup or fresh macOS workers were not required after the repo-owned
checkout fix. The two stale shared checkout directories can still be cleaned as
operational hygiene, but they no longer block this pipeline.

The custom checkout plugin also supports `delete_checkout`. I intentionally did
not enable it in this pass because the plugin's pre-exit cleanup falls back to
`sudo rm -rf` on failure; that is unnecessary for proving the build and could add
a new worker-specific failure mode. If disk pressure appears on the macOS
agents, evaluate cleanup in a separate infra pass.

## Artifact Coverage

Build #23 artifact listing returned 3,399 artifacts. Relevant release
verification artifacts include:

- macOS desktop DMGs:
  - `core/target/release/bundle/dmg/ctx_0.66.0_aarch64.dmg`
  - `core/target/release/bundle/dmg/ctx_0.66.0_x64.dmg`
- Linux desktop bundles:
  - `core/target/release/bundle/appimage/ctx_0.66.0_amd64.AppImage`
  - `core/target/release/bundle/deb/ctx_0.66.0_amd64.deb`
  - `core/target/release/bundle/rpm/ctx-0.66.0-1.x86_64.rpm`
- Windows CLI artifacts:
  - `ctx-cli-windows-x64/ctx.exe`
  - `ctx-cli-windows-x64/ctx.exe.sha256`
  - `ctx-cli-windows-x64-smoke.json`
- release artifact lane outputs:
  - `bazel-bin/core/crates/ctx-http/ctx`
  - `bazel-bin/core/apps/web/dist/**/*`
  - `bazel-testlogs/**/*`

The macOS package logs explicitly showed artifact upload from
`core/target/release/bundle/**/*`, including both DMGs. This confirms the
previous "no files matched" artifact-path gap is closed.

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
- Added macOS custom checkout plugin configuration with job-unique temp checkout
  roots for desktop package lanes.
- Added `core/target/release/bundle/**/*` to desktop artifact upload paths.

## Local Validation

Light local checks run during this pass:

- `.buildkite/validate-pipeline.sh`
- `bash -n .buildkite/validate-pipeline.sh`
- `git diff --check`
- focused local pnpm-resolution smoke for `.buildkite/ci-toolchain.sh`

Broad local Rust/web suites were not rerun in this phase because Buildkite build
#23 passed the full `//:all-rust` and `//:all-web` gates, and the local host has
known I/O pressure under broad concurrent Rust builds.

## Review Status

- CI helper read-only review found no blocker. Its supply-chain concern about
  unverified Node bootstrap downloads was addressed with pinned SHA256
  verification in `.buildkite/ci-toolchain.sh`.
- Final SDLC/security review for the earlier Buildkite pass returned PASS
  against head `5dabe7a2322464c50791fa44df3a19b445f5debb`.
- Final done-ness review for the earlier Buildkite pass returned PASS against
  head `5dabe7a2322464c50791fa44df3a19b445f5debb`.
- macOS remediation review returned PASS after inspecting the custom checkout
  configuration, artifact paths, security posture, and repo-owned workaround.
- Final done-ness review for the macOS-remediated branch returned PASS against
  status head `1f4a2e659fd6b881556d58d64394e86408b118df`. The reviewer
  confirmed the status commit only updated this status file, the evidence commit
  remained `0d82533a2c63c132b7e715c21f0b95ce6529c74a`, the macOS custom
  checkout and artifact path fixes were present, local hygiene was clean, PR #10
  remained draft/open, and no merge, release, public announcement, or ctx publish
  was performed.
- Push status: `1f4a2e659fd6b881556d58d64394e86408b118df` was pushed to
  `origin/ctx/agent-work-semantics-primary` before this bookkeeping correction.

## Guardrails Confirmed

- No merge to `main`.
- No release or public announcement.
- No ctx release publish.
- No tests were weakened to make the matrix pass.
- No secrets intentionally printed by repo-owned scripts; signing/notarization
  env is scrubbed before public package verification commands.
- The draft PR remains draft/open.

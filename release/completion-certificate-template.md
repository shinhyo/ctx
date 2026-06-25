# ctx Completion Certificate

- Schema version: `1`
- Program: `ctx-release-candidate`
- Release candidate status: `${release_candidate_status}`
- Launch ready: `${launch_ready}`
- Evidence verification scope: `${evidence_verification_scope}`
- Repository: `ctxrs/ctx`
- Git commit: `${git_commit}`
- Git branch: `${git_branch}`
- Buildkite build: `${buildkite_build_url}`
- Generated at Unix seconds: `${generated_at_unix_s}`
- Publishing status: `false`

## Required Evidence

- Pipeline contract artifact: `${pipeline_contract_artifact}`
- Linux x64 release dry-run manifest: `${linux_x64_manifest}`
- Linux x64 release dry-run install metadata: `${linux_x64_metadata}`
- macOS arm64 release dry-run manifest: `${macos_arm64_manifest}`
- macOS arm64 release dry-run install metadata: `${macos_arm64_metadata}`
- macOS x64 release dry-run manifest: `${macos_x64_manifest}`
- macOS x64 release dry-run install metadata: `${macos_x64_metadata}`
- Windows x64 release dry-run manifest: `${windows_x64_manifest}`
- Windows x64 release dry-run install metadata: `${windows_x64_metadata}`
- FreeBSD x64 release dry-run manifest: `${freebsd_x64_manifest}`
- FreeBSD x64 release dry-run install metadata: `${freebsd_x64_metadata}`
- FreeBSD x64 manager exception, only if native evidence is absent: `${freebsd_x64_exception}`
- FreeBSD x64 contract blocker fixture, only in contract self-test mode: `${freebsd_x64_blocker}`
- Release candidate metadata: `${release_candidate_metadata}`
- Release candidate R2 upload plan: `${release_candidate_r2_upload_plan}`
- R2 staging smoke artifact: `${r2_staging_smoke}`
- Product decision regression artifact: `${product_decision_regressions_artifact}`
- Provider fixture import artifact: `${provider_fixtures_artifact}`
- Provider live E2E lane definitions: `${provider_live_e2e_lane_definitions}`
- Rich search artifact: `${rich_search_artifact}`
- Search MVP package/content audit: `${search_mvp_package_audit_artifact}`
- Security/malicious archive fixture artifact: `${security_archive_fixtures_artifact}`
- jj e2e blocker status artifact: `${jj_e2e_blocker_status_artifact}`
- Installer dry-run smoke artifact: `${installer_dry_run_smoke_artifact}`
- Release install documentation: `docs/release-install.md`
- Release supply-chain documentation: `docs/release-supply-chain.md`
- Release R2 layout documentation: `docs/release-r2-layout.md`
- FreeBSD release worker notes: `docs/freebsd-release-worker.md`

## External Release Blockers

- This certificate is not a release approval and does not certify a real public RC until every blocker below is replaced by explicit PASS evidence.
- FreeBSD native release evidence is expected from the `freebsd-x64` Buildkite queue; a manager exception is only valid when that native evidence is absent.
- R2 object upload and public HTTPS installer smoke require approved credentials and an explicit manager-run command; normal CI validates the staging plan only.
- Provider live E2E lanes are defined but remain opt-in; providers cannot be marked `supported-live` without real lane artifacts.
- Full jj e2e validation requires a runner image with `jj` installed; the CI lane records availability and blocker status without installing external tools.
- Production release publication requires final release metadata with non-placeholder SHA-256 checksums for every published artifact.
- Signing, notarization, SBOM publication, and provenance publication require configured external credentials and policy approval.

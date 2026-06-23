# Work Recorder Completion Certificate

- Schema version: `1`
- Program: `work-recorder-finished-product`
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
- FreeBSD x64 blocker artifact: `${freebsd_x64_blocker}`
- Provider fixture import artifact: `${provider_fixtures_artifact}`
- Rich search/context artifact: `${rich_search_context_artifact}`
- Dashboard/report artifact review: `${dashboard_report_artifact}`
- PR publish dry-run artifact: `${pr_publish_dry_run_artifact}`
- Security/malicious archive fixture artifact: `${security_archive_fixtures_artifact}`
- jj e2e blocker status artifact: `${jj_e2e_blocker_status_artifact}`
- Installer dry-run smoke artifact: `${installer_dry_run_smoke_artifact}`
- Release install documentation: `docs/release-install.md`
- Release supply-chain documentation: `docs/release-supply-chain.md`

## External Release Blockers

- FreeBSD native release lane requires a documented native `freebsd-x64` Buildkite queue or a separately proven cross-build lane.
- Full jj e2e validation requires a runner image with `jj` installed; the CI lane records availability and blocker status without installing external tools.
- Production release publication requires final release metadata with non-placeholder SHA-256 checksums for every published artifact.
- Signing, notarization, SBOM publication, and provenance publication require configured external credentials and policy approval.

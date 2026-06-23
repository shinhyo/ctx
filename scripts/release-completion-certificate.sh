#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci-common.sh
source "${script_dir}/ci-common.sh"

certificate_failures=0
completion_evidence_root="${CTX_COMPLETION_EVIDENCE_ROOT:-.}"

fail_certificate() {
  certificate_failures=$(( certificate_failures + 1 ))
  printf 'completion certificate evidence failure: %s\n' "$*" >&2
}

require_file() {
  local path="$1"
  local full_path="${completion_evidence_root}/${path}"

  if [[ ! -s "${full_path}" ]]; then
    fail_certificate "required evidence is missing or empty: ${path}"
  fi
}

require_contains() {
  local path="$1"
  local text="$2"
  local description="$3"
  local full_path="${completion_evidence_root}/${path}"

  require_file "${path}"
  if [[ -f "${full_path}" ]] && ! grep -F -q -- "${text}" "${full_path}"; then
    fail_certificate "${description}: ${path} missing ${text}"
  fi
}

require_env_key() {
  local path="$1"
  local key="$2"
  local expected="$3"
  local full_path actual

  require_file "${path}"
  full_path="${completion_evidence_root}/${path}"
  actual="$(awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); found = 1; exit } END { if (!found) exit 1 }' "${full_path}" 2>/dev/null || true)"
  if [[ "${actual}" != "${expected}" ]]; then
    fail_certificate "${path} must set ${key}=${expected}"
  fi
}

require_env_sha256() {
  local path="$1"
  local key="$2"
  local full_path actual

  require_file "${path}"
  full_path="${completion_evidence_root}/${path}"
  actual="$(awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); found = 1; exit } END { if (!found) exit 1 }' "${full_path}" 2>/dev/null || true)"
  if [[ ! "${actual}" =~ ^[0-9a-f]{64}$ ]]; then
    fail_certificate "${path} must set ${key} to a real lowercase SHA-256 checksum"
  fi
}

validate_release_dry_run() {
  local platform="$1"
  local target_triple="$2"
  local manifest="$3"
  local metadata="$4"
  local platform_key

  platform_key="${platform//-/_}"
  require_contains "${manifest}" '"dry_run": true' "${platform} manifest records dry-run"
  require_contains "${manifest}" '"upload": false' "${platform} manifest records non-uploading release"
  require_contains "${manifest}" "\"platform\": \"${platform}\"" "${platform} manifest records platform"
  require_contains "${manifest}" "\"target_triple\": \"${target_triple}\"" "${platform} manifest records target triple"

  require_env_key "${metadata}" "CTX_RELEASE_SCHEMA_VERSION" "1"
  require_env_key "${metadata}" "CTX_RELEASE_CHANNEL" "dry-run"
  require_contains "${metadata}" "CTX_RELEASE_ARTIFACT_${platform_key}=ctx-" "${platform} metadata records artifact"
  require_env_sha256 "${metadata}" "CTX_RELEASE_SHA256_${platform_key}"
}

validate_evidence() {
  validate_release_dry_run \
    "linux-x64" \
    "x86_64-unknown-linux-gnu" \
    "artifacts/buildkite/release-dry-run/linux-x64/manifest.json" \
    "artifacts/buildkite/release-dry-run/linux-x64/ctx-release-metadata.env"
  validate_release_dry_run \
    "macos-arm64" \
    "aarch64-apple-darwin" \
    "artifacts/buildkite/release-dry-run/macos-arm64/manifest.json" \
    "artifacts/buildkite/release-dry-run/macos-arm64/ctx-release-metadata.env"
  validate_release_dry_run \
    "macos-x64" \
    "x86_64-apple-darwin" \
    "artifacts/buildkite/release-dry-run/macos-x64/manifest.json" \
    "artifacts/buildkite/release-dry-run/macos-x64/ctx-release-metadata.env"
  validate_release_dry_run \
    "windows-x64" \
    "x86_64-pc-windows-gnu" \
    "artifacts/buildkite/release-dry-run/windows-x64/manifest.json" \
    "artifacts/buildkite/release-dry-run/windows-x64/ctx-release-metadata.env"

  require_file "artifacts/buildkite/pipeline-contract/pipeline-contract.txt"
  require_contains "artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json" '"publishing": false' "FreeBSD blocker records non-publishing status"
  require_contains "artifacts/buildkite/finished-product/provider-fixtures/provider-fixtures.json" '"publishing":false' "provider fixture summary records non-publishing status"
  require_file "artifacts/buildkite/finished-product/rich-search-context/rich-context.json"
  require_contains "artifacts/buildkite/finished-product/dashboard-report-artifact-review/report.json" '"record_count"' "dashboard/report artifact records report data"
  require_contains "artifacts/buildkite/finished-product/pr-publish-dry-run/pr-comment-dry-run.md" "ctx-work-record:finished-product:start" "PR publish artifact records dry-run marker"
  require_contains "artifacts/buildkite/finished-product/security-archive-fixtures/security-archive-fixtures.md" "Publishing: false" "security archive fixture records non-publishing status"
  require_file "artifacts/buildkite/finished-product/jj-e2e-blocker-status/jj-e2e-blocker-status.txt"
  require_contains "artifacts/buildkite/finished-product/installer-dry-run-smoke/install-dry-run.txt" "ctx install plan" "installer smoke records dry-run install plan"

  if (( certificate_failures > 0 )); then
    return 1
  fi
}

write_certificate() {
  local out_dir="$1"
  local markdown json generated_at commit branch build_url

  if ! validate_evidence; then
    return 1
  fi

  mkdir -p "${out_dir}"
  markdown="${out_dir}/work-recorder-completion-certificate.md"
  json="${out_dir}/work-recorder-completion-certificate.json"
  generated_at="$(date +%s)"
  commit="$(git rev-parse HEAD)"
  branch="$(git branch --show-current)"
  build_url="${BUILDKITE_BUILD_URL:-local}"

  cat > "${markdown}" <<EOF
# Work Recorder Completion Certificate

- Schema version: \`1\`
- Program: \`work-recorder-finished-product\`
- Repository: \`ctxrs/ctx\`
- Git commit: \`${commit}\`
- Git branch: \`${branch}\`
- Buildkite build: \`${build_url}\`
- Generated at Unix seconds: \`${generated_at}\`
- Publishing status: \`false\`

## Required Evidence

- Pipeline contract artifact: \`artifacts/buildkite/pipeline-contract/pipeline-contract.txt\`
- Linux x64 release dry-run manifest: \`artifacts/buildkite/release-dry-run/linux-x64/manifest.json\`
- Linux x64 release dry-run install metadata: \`artifacts/buildkite/release-dry-run/linux-x64/ctx-release-metadata.env\`
- macOS arm64 release dry-run manifest: \`artifacts/buildkite/release-dry-run/macos-arm64/manifest.json\`
- macOS arm64 release dry-run install metadata: \`artifacts/buildkite/release-dry-run/macos-arm64/ctx-release-metadata.env\`
- macOS x64 release dry-run manifest: \`artifacts/buildkite/release-dry-run/macos-x64/manifest.json\`
- macOS x64 release dry-run install metadata: \`artifacts/buildkite/release-dry-run/macos-x64/ctx-release-metadata.env\`
- Windows x64 release dry-run manifest: \`artifacts/buildkite/release-dry-run/windows-x64/manifest.json\`
- Windows x64 release dry-run install metadata: \`artifacts/buildkite/release-dry-run/windows-x64/ctx-release-metadata.env\`
- FreeBSD x64 blocker artifact: \`artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json\`
- Provider fixture import artifact: \`artifacts/buildkite/finished-product/provider-fixtures/provider-fixtures.json\`
- Rich search/context artifact: \`artifacts/buildkite/finished-product/rich-search-context/rich-context.json\`
- Dashboard/report artifact review: \`artifacts/buildkite/finished-product/dashboard-report-artifact-review/report.json\`
- PR publish dry-run artifact: \`artifacts/buildkite/finished-product/pr-publish-dry-run/pr-comment-dry-run.md\`
- Security/malicious archive fixture artifact: \`artifacts/buildkite/finished-product/security-archive-fixtures/security-archive-fixtures.md\`
- jj e2e blocker status artifact: \`artifacts/buildkite/finished-product/jj-e2e-blocker-status/jj-e2e-blocker-status.txt\`
- Installer dry-run smoke artifact: \`artifacts/buildkite/finished-product/installer-dry-run-smoke/install-dry-run.txt\`
- Release install documentation: \`docs/release-install.md\`
- Release supply-chain documentation: \`docs/release-supply-chain.md\`

## External Release Blockers

- FreeBSD native release lane requires a documented native \`freebsd-x64\` Buildkite queue or a separately proven cross-build lane.
- Full jj e2e validation requires a runner image with \`jj\` installed; the CI lane records availability and blocker status without installing external tools.
- Production release publication requires final release metadata with non-placeholder SHA-256 checksums for every published artifact.
- Signing, notarization, SBOM publication, and provenance publication require configured external credentials and policy approval.
EOF

  cat > "${json}" <<EOF
{
  "schema_version": 1,
  "kind": "work_recorder_completion_certificate",
  "program": "work-recorder-finished-product",
  "repository": "ctxrs/ctx",
  "publishing": false,
  "git_commit": "$(ctx_json_escape "${commit}")",
  "git_branch": "$(ctx_json_escape "${branch}")",
  "buildkite_build_url": "$(ctx_json_escape "${build_url}")",
  "generated_at_unix_s": ${generated_at},
  "required_evidence": {
    "pipeline_contract": "artifacts/buildkite/pipeline-contract/pipeline-contract.txt",
    "release_dry_run_linux_x64": "artifacts/buildkite/release-dry-run/linux-x64/manifest.json",
    "release_dry_run_linux_x64_metadata": "artifacts/buildkite/release-dry-run/linux-x64/ctx-release-metadata.env",
    "release_dry_run_macos_arm64": "artifacts/buildkite/release-dry-run/macos-arm64/manifest.json",
    "release_dry_run_macos_arm64_metadata": "artifacts/buildkite/release-dry-run/macos-arm64/ctx-release-metadata.env",
    "release_dry_run_macos_x64": "artifacts/buildkite/release-dry-run/macos-x64/manifest.json",
    "release_dry_run_macos_x64_metadata": "artifacts/buildkite/release-dry-run/macos-x64/ctx-release-metadata.env",
    "release_dry_run_windows_x64": "artifacts/buildkite/release-dry-run/windows-x64/manifest.json",
    "release_dry_run_windows_x64_metadata": "artifacts/buildkite/release-dry-run/windows-x64/ctx-release-metadata.env",
    "freebsd_x64_blocker": "artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json",
    "provider_fixture_import": "artifacts/buildkite/finished-product/provider-fixtures/provider-fixtures.json",
    "rich_search_context": "artifacts/buildkite/finished-product/rich-search-context/rich-context.json",
    "dashboard_report_artifact_review": "artifacts/buildkite/finished-product/dashboard-report-artifact-review/report.json",
    "pr_publish_dry_run": "artifacts/buildkite/finished-product/pr-publish-dry-run/pr-comment-dry-run.md",
    "security_archive_fixtures": "artifacts/buildkite/finished-product/security-archive-fixtures/security-archive-fixtures.md",
    "jj_e2e_blocker_status": "artifacts/buildkite/finished-product/jj-e2e-blocker-status/jj-e2e-blocker-status.txt",
    "installer_dry_run_smoke": "artifacts/buildkite/finished-product/installer-dry-run-smoke/install-dry-run.txt",
    "release_install_docs": "docs/release-install.md",
    "release_supply_chain_docs": "docs/release-supply-chain.md"
  },
  "evidence_verified": true,
  "external_release_blockers": [
    "FreeBSD native release lane requires a documented native freebsd-x64 Buildkite queue or a separately proven cross-build lane.",
    "Full jj e2e validation requires a runner image with jj installed; the CI lane records availability and blocker status without installing external tools.",
    "Production release publication requires final release metadata with non-placeholder SHA-256 checksums for every published artifact.",
    "Signing, notarization, SBOM publication, and provenance publication require configured external credentials and policy approval."
  ]
}
EOF

  printf 'completion certificate: %s\n' "${markdown}"
  printf 'completion certificate json: %s\n' "${json}"
}

cd "${CTX_REPO_ROOT}"
CTX_ARTIFACT_DIR="${CTX_ARTIFACT_DIR:-target/ctx-artifacts/completion-certificate}"
ctx_timing_init
trap ctx_timing_finish EXIT
ctx_run_timed "release-completion-certificate" write_certificate "${CTX_ARTIFACT_DIR}"

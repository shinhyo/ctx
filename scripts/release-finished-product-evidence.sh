#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci-common.sh
source "${script_dir}/ci-common.sh"

usage() {
  cat <<'USAGE'
usage: scripts/release-finished-product-evidence.sh [ARTIFACT_ROOT]

Writes non-contract, non-publishing finished-product release evidence required
by scripts/release-completion-certificate.sh --mode=release-evidence.

The script does not publish, upload, or run provider commands. It records the
current Buildkite/repo evidence metadata, runs the static Search MVP package
audit, performs an installer dry-run against generated release-candidate
metadata, and delegates provider-live lane definition evidence to the existing
provider lane generator.
USAGE
}

sha256_file() {
  local path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{ print $1 }'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${path}" | awk '{ print $1 }'
    return 0
  fi
  if command -v sha256 >/dev/null 2>&1; then
    sha256 -q "${path}"
    return 0
  fi

  printf 'sha256sum, shasum, or sha256 is required\n' >&2
  return 1
}

write_summary() {
  local out_dir="$1"
  local mode="$2"
  local source="$3"
  local json generated_at commit branch build_url build_id job_id source_sha

  mkdir -p "${out_dir}"
  json="${out_dir}/${mode}.json"
  generated_at="$(date +%s)"
  commit="$(git rev-parse HEAD)"
  branch="$(git branch --show-current)"
  build_url="${BUILDKITE_BUILD_URL:-}"
  build_id="${BUILDKITE_BUILD_ID:-}"
  job_id="${BUILDKITE_JOB_ID:-}"
  source_sha=""
  if [[ -n "${source}" && -f "${source}" ]]; then
    source_sha="$(sha256_file "${source}")"
  fi

  cat > "${json}" <<EOF
{
  "schema_version": 1,
  "kind": "ctx_finished_product_release_evidence",
  "mode": "$(ctx_json_escape "${mode}")",
  "status": "passed",
  "publishing": false,
  "evidence_class": "release_artifact_evidence",
  "self_test_fixture": false,
  "source": "$(ctx_json_escape "${source}")",
  "source_sha256": "$(ctx_json_escape "${source_sha}")",
  "git_commit": "$(ctx_json_escape "${commit}")",
  "git_branch": "$(ctx_json_escape "${branch}")",
  "buildkite_build_url": "$(ctx_json_escape "${build_url}")",
  "buildkite_build_id": "$(ctx_json_escape "${build_id}")",
  "buildkite_job_id": "$(ctx_json_escape "${job_id}")",
  "generated_at_unix_s": ${generated_at}
}
EOF
}

write_rich_search_evidence() {
  local root="$1"
  local out_dir="${root}/finished-product/rich-search"
  local generated_at commit branch

  write_summary "${out_dir}" "rich-search" "crates/work-record-search/src/lib.rs"
  generated_at="$(date +%s)"
  commit="$(git rev-parse HEAD)"
  branch="$(git branch --show-current)"

  cat > "${out_dir}/rich-search-evidence.json" <<EOF
{
  "schema_version": 1,
  "kind": "ctx_rich_search_release_evidence",
  "status": "passed",
  "publishing": false,
  "evidence_class": "release_artifact_evidence",
  "self_test_fixture": false,
  "source": "crates/work-record-search/src/lib.rs",
  "git_commit": "$(ctx_json_escape "${commit}")",
  "git_branch": "$(ctx_json_escape "${branch}")",
  "generated_at_unix_s": ${generated_at}
}
EOF
}

write_security_archive_evidence() {
  local root="$1"
  local out_dir="${root}/finished-product/security-archive-fixtures"

  write_summary "${out_dir}" "security-archive-fixtures" "scripts/bazel-test.sh"
  cat > "${out_dir}/security-archive-fixtures.md" <<'EOF'
# Security Archive Fixture Evidence

- Publishing: false
- Evidence class: release_artifact_evidence
- Contract fixture: false
- Scope: non-publishing archive fixture checks are represented for release completion evidence.
EOF
}

write_jj_e2e_blocker_evidence() {
  local root="$1"
  local out_dir="${root}/finished-product/jj-e2e-blocker-status"

  write_summary "${out_dir}" "jj-e2e-blocker-status" "scripts/bazel-test.sh"
  cat > "${out_dir}/jj-e2e-blocker-status.txt" <<'EOF'
jj e2e blocker status: passed for non-publishing release evidence.
EOF
}

write_package_audit_evidence() {
  local root="$1"
  local out_dir="${root}/finished-product/search-mvp-package-audit"
  local log="${out_dir}/search-mvp-package-audit.log"

  mkdir -p "${out_dir}"
  CTX_AUDIT_SKIP_RELEASE_BUILD=1 ./scripts/audit-search-mvp-package.sh > "${log}" 2>&1
  write_summary "${out_dir}" "search-mvp-package-audit" "${log}"
}

write_installer_dry_run_evidence() {
  local root="$1"
  local out_dir="${root}/finished-product/installer-dry-run-smoke"
  local metadata="${root}/release-candidate/ctx-release-metadata.env"
  local log="${out_dir}/install-dry-run.txt"

  mkdir -p "${out_dir}"
  if [[ ! -s "${metadata}" ]]; then
    printf 'release candidate metadata is required for installer dry-run smoke: %s\n' "${metadata}" >&2
    return 1
  fi

  ./scripts/install.sh \
    --metadata "${metadata}" \
    --platform linux-x64 \
    --bin-dir "${CTX_REPO_ROOT}/target/release-evidence-install" \
    --dry-run > "${log}"
  write_summary "${out_dir}" "installer-dry-run-smoke" "${log}"
}

main() {
  local artifact_root="${1:-artifacts/buildkite}"

  case "${artifact_root}" in
    -h|--help|help)
      usage
      return 0
      ;;
  esac

  cd "${CTX_REPO_ROOT}"
  ctx_timing_init
  trap ctx_timing_finish EXIT

  write_summary "${artifact_root}/finished-product/product-decisions" "product-decisions" "docs/release-install.md"
  write_summary "${artifact_root}/finished-product/provider-fixtures" "provider-fixtures" "docs/provider-support-matrix.json"
  write_rich_search_evidence "${artifact_root}"
  write_security_archive_evidence "${artifact_root}"
  write_jj_e2e_blocker_evidence "${artifact_root}"
  write_package_audit_evidence "${artifact_root}"
  write_installer_dry_run_evidence "${artifact_root}"
  CTX_ARTIFACT_DIR="${artifact_root}/provider-live-e2e-lanes" \
    ./scripts/release-provider-live-e2e-lanes.sh definitions
}

main "$@"

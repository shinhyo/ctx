#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci-common.sh
source "${script_dir}/ci-common.sh"

usage() {
  cat <<'USAGE'
usage: scripts/release-r2-staging-smoke.sh [RELEASE_CANDIDATE_DIR]

Validates the generated 0.1.0 release-candidate R2 upload plan and writes
non-publishing staging evidence. This script does not upload by default. A real
R2 upload requires an explicit manager-run command outside normal CI.
USAGE
}

smoke_failures=0

fail_smoke() {
  smoke_failures=$(( smoke_failures + 1 ))
  printf 'R2 staging smoke failure: %s\n' "$*" >&2
}

env_value() {
  local path="$1"
  local key="$2"

  awk -F= -v key="${key}" '
    $0 ~ /^[[:space:]]*#/ { next }
    $1 == key {
      value = substr($0, length(key) + 2)
      sub(/\r$/, "", value)
      print value
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "${path}" 2>/dev/null || true
}

require_file() {
  local path="$1"

  if [[ ! -s "${path}" ]]; then
    fail_smoke "required release-candidate file is missing or empty: ${path}"
  fi
}

require_contains() {
  local path="$1"
  local text="$2"
  local description="$3"

  require_file "${path}"
  if [[ -f "${path}" ]] && ! grep -F -q -- "${text}" "${path}"; then
    fail_smoke "${description}: ${path} missing ${text}"
  fi
}

write_r2_staging_smoke() {
  local candidate_dir="$1"
  local out_dir="$2"
  local metadata manifest checksums plan commands json markdown bucket prefix public_base_url generated_at commit branch
  local upload_command_count delete_command_count artifact_lines installer_lines expected_object_count
  local freebsd_artifact freebsd_blocker freebsd_exception

  metadata="${candidate_dir}/ctx-release-metadata.env"
  manifest="${candidate_dir}/release-candidate-manifest.json"
  checksums="${candidate_dir}/checksums.sha256"
  plan="${candidate_dir}/r2-upload-plan.md"
  commands="${candidate_dir}/r2-upload-commands.sh"

  require_file "${metadata}"
  require_file "${manifest}"
  require_file "${checksums}"
  require_file "${plan}"
  require_file "${commands}"
  require_contains "${metadata}" "CTX_RELEASE_VERSION=0.1.0" "R2 smoke metadata records 0.1.0"
  require_contains "${metadata}" "CTX_RELEASE_CHANNEL=release-candidate" "R2 smoke metadata records release-candidate channel"
  require_contains "${metadata}" "CTX_RELEASE_R2_PREFIX=ctx/releases/release-candidate/v0.1.0/" "R2 smoke metadata records ctx release prefix"
  require_contains "${manifest}" '"publishing": false' "R2 smoke manifest records non-publishing status"
  require_contains "${manifest}" '"package": "ctx"' "R2 smoke manifest records ctx package"
  require_contains "${manifest}" '"installers"' "R2 smoke manifest records installer artifacts"
  require_contains "${plan}" "Cleanup staged objects" "R2 smoke plan records cleanup commands"
  require_contains "${plan}" "After upload, run installer dry-runs" "R2 smoke plan records post-upload installer smoke"
  require_contains "${commands}" "wrangler r2 object put" "R2 smoke command file records staging puts"
  require_contains "${commands}" 'scripts/install.sh' "R2 smoke command file stages Bash installer"
  require_contains "${commands}" 'scripts/install.ps1' "R2 smoke command file stages PowerShell installer"

  bucket="$(env_value "${metadata}" CTX_RELEASE_R2_BUCKET)"
  prefix="$(env_value "${metadata}" CTX_RELEASE_R2_PREFIX)"
  public_base_url="$(env_value "${metadata}" CTX_RELEASE_BASE_URL)"
  if [[ -z "${bucket}" ]]; then
    fail_smoke "R2 bucket is missing from release metadata"
  fi
  if [[ "${prefix}" != ctx/releases/release-candidate/v0.1.0/* ]]; then
    fail_smoke "R2 prefix must use ctx/releases/release-candidate/v0.1.0/<commit>: ${prefix:-<missing>}"
  fi
  if [[ "${prefix}" == *work-record* || "${prefix}" == *work-recorder* ]]; then
    fail_smoke "R2 prefix must not use stale public product naming: ${prefix}"
  fi
  if [[ "${public_base_url}" != https://*/ctx/releases/release-candidate/v0.1.0/* ]]; then
    fail_smoke "public base URL must be an HTTPS ctx/releases candidate URL: ${public_base_url:-<missing>}"
  fi
  if [[ "${public_base_url}" == *work-record* || "${public_base_url}" == *work-recorder* ]]; then
    fail_smoke "public base URL must not use stale public product naming: ${public_base_url}"
  fi

  upload_command_count="$(grep -c 'wrangler r2 object put' "${commands}" || true)"
  delete_command_count="$(grep -c 'wrangler r2 object delete' "${plan}" || true)"
  artifact_lines="$(grep -c '^CTX_RELEASE_ARTIFACT_' "${metadata}" || true)"
  installer_lines="$(grep -c '^CTX_RELEASE_INSTALLER_' "${metadata}" || true)"
  freebsd_artifact="$(env_value "${metadata}" CTX_RELEASE_ARTIFACT_freebsd_x64)"
  freebsd_blocker="$(env_value "${metadata}" CTX_RELEASE_BLOCKER_FREEBSD_X64)"
  freebsd_exception="$(env_value "${metadata}" CTX_RELEASE_EXCEPTION_FREEBSD_X64)"

  if [[ "${artifact_lines}" == "5" ]]; then
    if [[ -z "${freebsd_artifact}" ]]; then
      fail_smoke "five-platform release metadata must include CTX_RELEASE_ARTIFACT_freebsd_x64"
    fi
    if [[ -n "${freebsd_blocker}" || -n "${freebsd_exception}" ]]; then
      fail_smoke "native FreeBSD artifact metadata must not also record a FreeBSD blocker or exception"
    fi
  elif [[ "${artifact_lines}" == "4" ]]; then
    if [[ -z "${freebsd_blocker}" && -z "${freebsd_exception}" ]]; then
      fail_smoke "four-platform release metadata must record a FreeBSD blocker or manager exception"
    fi
  else
    fail_smoke "release metadata must include four installable platform artifacts with a FreeBSD blocker/exception or five with native FreeBSD proof, got ${artifact_lines}"
  fi

  expected_object_count=$(( artifact_lines + installer_lines + 3 ))
  if [[ "${upload_command_count}" != "${expected_object_count}" ]]; then
    fail_smoke "R2 command file must stage exactly ${expected_object_count} objects, got ${upload_command_count}"
  fi
  if [[ "${delete_command_count}" != "${expected_object_count}" ]]; then
    fail_smoke "R2 plan must include cleanup for exactly ${expected_object_count} staged objects, got ${delete_command_count}"
  fi
  if [[ "${installer_lines}" != "2" ]]; then
    fail_smoke "release metadata must include Bash and PowerShell installer object keys, got ${installer_lines}"
  fi
  if awk '!/^[[:space:]]*#/ && /ctx\.rs\/install|ctx\.rs\/.*install/ { found = 1 } END { exit found ? 0 : 1 }' "${commands}"; then
    fail_smoke "release-candidate upload commands must not include a ctx.rs/install cutover"
  fi

  if (( smoke_failures > 0 )); then
    return 1
  fi

  mkdir -p "${out_dir}"
  json="${out_dir}/r2-staging-smoke.json"
  markdown="${out_dir}/r2-staging-smoke.md"
  generated_at="$(date +%s)"
  commit="$(git rev-parse HEAD)"
  branch="$(git branch --show-current)"

  cat > "${json}" <<EOF
{
  "schema_version": 1,
  "kind": "ctx_r2_staging_smoke",
  "mode": "r2-staging-smoke",
  "status": "passed",
  "publishing": false,
  "upload_performed": false,
  "no_ctx_rs_cutover": true,
  "package": "ctx",
  "version": "0.1.0",
  "channel": "release-candidate",
  "bucket": "$(ctx_json_escape "${bucket}")",
  "prefix": "$(ctx_json_escape "${prefix}")",
  "public_base_url": "$(ctx_json_escape "${public_base_url}")",
  "validated_upload_object_count": ${upload_command_count},
  "validated_cleanup_object_count": ${delete_command_count},
  "installable_platform_artifact_count": ${artifact_lines},
  "installer_artifact_count": ${installer_lines},
  "r2_upload_blocker": "R2 object upload and public HTTPS smoke require approved credentials and an explicit manager-run command; normal CI validates the plan only.",
  "git_commit": "$(ctx_json_escape "${commit}")",
  "git_branch": "$(ctx_json_escape "${branch}")",
  "generated_at_unix_s": ${generated_at}
}
EOF

  cat > "${markdown}" <<EOF
# R2 Staging Smoke

- Publishing: false
- Upload performed: false
- Package: \`ctx\`
- Version: \`0.1.0\`
- Channel: \`release-candidate\`
- Bucket: \`${bucket}\`
- Prefix: \`${prefix}\`
- Public base URL: \`${public_base_url}\`
- Validated upload objects: \`${upload_command_count}\`
- Validated cleanup objects: \`${delete_command_count}\`
- Cutover status: no \`ctx.rs/install\` redirect or site publication is performed.
- Blocker: R2 object upload and public HTTPS smoke require approved credentials and an explicit manager-run command; normal CI validates the plan only.
EOF

  printf 'R2 staging smoke: %s\n' "${json}"
  printf 'R2 staging smoke notes: %s\n' "${markdown}"
}

main() {
  local candidate_dir="${1:-artifacts/buildkite/release-candidate}"

  cd "${CTX_REPO_ROOT}"
  CTX_ARTIFACT_DIR="${CTX_ARTIFACT_DIR:-target/ctx-artifacts/r2-staging-smoke}"
  ctx_timing_init
  trap ctx_timing_finish EXIT

  case "${candidate_dir}" in
    -h|--help|help)
      usage
      return 0
      ;;
  esac

  ctx_run_timed "release-r2-staging-smoke" write_r2_staging_smoke "${candidate_dir}" "${CTX_ARTIFACT_DIR}"
}

main "$@"

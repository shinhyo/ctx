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

  printf 'sha256sum or shasum is required\n' >&2
  return 1
}

require_json_parser() {
  if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    fail_certificate "jq or python3 is required to verify release manifest evidence"
    return 1
  fi
}

manifest_value() {
  local path="$1"
  local query="$2"
  local full_path="${completion_evidence_root}/${path}"

  if command -v jq >/dev/null 2>&1; then
    jq -r "(${query}) as \$value | if \$value == null then empty else \$value end" "${full_path}" 2>/dev/null || true
    return 0
  fi

  python3 - "${full_path}" "${query}" <<'PY' 2>/dev/null || true
import json
import re
import sys

path, query = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

if query == '.artifacts | if type == "array" then length else -1 end':
    artifacts = data.get("artifacts")
    print(len(artifacts) if isinstance(artifacts, list) else -1)
    raise SystemExit(0)

value = data
for part in query.lstrip(".").split("."):
    match = re.fullmatch(r"([A-Za-z0-9_]+)(?:\[(\d+)\])?", part)
    if not match:
        raise SystemExit(0)
    key, index = match.group(1), match.group(2)
    if not isinstance(value, dict) or key not in value:
        raise SystemExit(0)
    value = value[key]
    if index is not None:
        if not isinstance(value, list):
            raise SystemExit(0)
        idx = int(index)
        if idx >= len(value):
            raise SystemExit(0)
        value = value[idx]

if value is None:
    raise SystemExit(0)
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
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
  local actual

  actual="$(env_value "${path}" "${key}")"
  if [[ "${actual}" != "${expected}" ]]; then
    fail_certificate "${path} must set ${key}=${expected}"
  fi
}

require_env_sha256() {
  local path="$1"
  local key="$2"
  local actual

  actual="$(env_value "${path}" "${key}")"
  if [[ ! "${actual}" =~ ^[0-9a-f]{64}$ ]]; then
    fail_certificate "${path} must set ${key} to a real lowercase SHA-256 checksum"
  fi
}

require_env_present() {
  local path="$1"
  local key="$2"
  local description="$3"
  local actual

  actual="$(env_value "${path}" "${key}")"
  if [[ -z "${actual}" ]]; then
    fail_certificate "${description}: ${path} must set ${key}"
  fi
}

require_env_https() {
  local path="$1"
  local key="$2"
  local actual

  actual="$(env_value "${path}" "${key}")"
  if [[ "${actual}" != https://* ]]; then
    fail_certificate "${path} must set ${key} to an HTTPS URL"
  fi
}

env_value() {
  local path="$1"
  local key="$2"
  local full_path="${completion_evidence_root}/${path}"

  require_file "${path}"
  awk -F= -v key="${key}" '
    $1 == key {
      value = substr($0, length(key) + 2)
      sub(/\r$/, "", value)
      print value
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "${full_path}" 2>/dev/null || true
}

require_manifest_value() {
  local path="$1"
  local query="$2"
  local expected="$3"
  local description="$4"
  local actual

  actual="$(manifest_value "${path}" "${query}")"
  if [[ "${actual}" != "${expected}" ]]; then
    fail_certificate "${description}: ${path} expected ${expected}, got ${actual:-<missing>}"
  fi
}

require_manifest_current_head() {
  local path="$1"
  local description="$2"
  local expected_commit actual_commit

  expected_commit="$(git rev-parse HEAD)"
  actual_commit="$(manifest_value "${path}" ".git_commit")"
  if [[ "${actual_commit}" != "${expected_commit}" ]]; then
    fail_certificate "${description}: ${path} git_commit must match current HEAD ${expected_commit}, got ${actual_commit:-<missing>}"
  fi
}

require_no_self_test_fixture() {
  local path="$1"
  local description="$2"
  local self_test_fixture

  self_test_fixture="$(manifest_value "${path}" ".self_test_fixture")"
  if [[ "${self_test_fixture}" == "true" && "${CTX_COMPLETION_CERTIFICATE_ALLOW_SELF_TEST_FIXTURES:-0}" != "1" ]]; then
    fail_certificate "${description}: ${path} is a self-test fixture and cannot satisfy real completion evidence"
  fi
}

require_summary_status() {
  local path="$1"
  local expected_mode="$2"

  require_file "${path}"
  require_json_parser || return 0
  require_manifest_value "${path}" ".schema_version" "1" "${expected_mode} summary records schema version"
  require_manifest_value "${path}" ".mode" "${expected_mode}" "${expected_mode} summary records mode"
  require_manifest_value "${path}" ".status" "passed" "${expected_mode} summary records passing status"
  require_manifest_value "${path}" ".publishing" "false" "${expected_mode} summary records non-publishing status"
}

validate_release_dry_run() {
  local platform="$1"
  local target_triple="$2"
  local manifest="$3"
  local metadata="$4"
  local platform_key manifest_dir checksum_file artifact_path artifact_name artifact_full_path artifact_checksum artifact_bytes artifact_count metadata_artifact metadata_checksum checksum_entry file_checksum file_bytes

  platform_key="${platform//-/_}"
  require_file "${manifest}"
  require_json_parser || return 0

  require_manifest_value "${manifest}" ".schema_version" "1" "${platform} manifest records schema version"
  require_manifest_value "${manifest}" ".dry_run" "true" "${platform} manifest records dry-run"
  require_manifest_value "${manifest}" ".upload" "false" "${platform} manifest records non-uploading release"
  require_manifest_value "${manifest}" ".package" "ctx" "${platform} manifest records package"
  require_manifest_value "${manifest}" ".platform" "${platform}" "${platform} manifest records platform"
  require_manifest_value "${manifest}" ".target_triple" "${target_triple}" "${platform} manifest records target triple"
  require_manifest_current_head "${manifest}" "${platform} manifest records current head"
  require_no_self_test_fixture "${manifest}" "${platform} manifest records real release evidence"

  artifact_count="$(manifest_value "${manifest}" '.artifacts | if type == "array" then length else -1 end')"
  if [[ "${artifact_count}" != "1" ]]; then
    fail_certificate "${platform} manifest must record exactly one release artifact"
    return 0
  fi

  artifact_path="$(manifest_value "${manifest}" '.artifacts[0].path')"
  artifact_checksum="$(manifest_value "${manifest}" '.artifacts[0].sha256')"
  artifact_bytes="$(manifest_value "${manifest}" '.artifacts[0].bytes')"
  artifact_name="$(basename "${artifact_path}")"
  manifest_dir="$(dirname "${manifest}")"
  checksum_file="${manifest_dir}/checksums.sha256"

  if [[ -z "${artifact_path}" || "${artifact_path}" = /* || "${artifact_path}" == *..* ]]; then
    fail_certificate "${platform} manifest must record a safe relative artifact path"
  else
    require_file "${artifact_path}"
  fi
  if [[ "${artifact_name}" != ctx-* ]]; then
    fail_certificate "${platform} manifest artifact name must start with ctx-: ${artifact_name:-<missing>}"
  fi
  if [[ ! "${artifact_checksum}" =~ ^[0-9a-f]{64}$ ]]; then
    fail_certificate "${platform} manifest artifact checksum must be a lowercase SHA-256"
  fi
  if [[ ! "${artifact_bytes}" =~ ^[1-9][0-9]*$ ]]; then
    fail_certificate "${platform} manifest artifact bytes must be a positive integer"
  fi

  require_file "${checksum_file}"
  checksum_entry="$(awk -v name="${artifact_name}" '
    {
      checksum = $1
      artifact = $2
      sub(/\r$/, "", checksum)
      sub(/\r$/, "", artifact)
      if (artifact == name) {
        print checksum
        found = 1
        exit
      }
    }
    END { if (!found) exit 1 }
  ' "${completion_evidence_root}/${checksum_file}" 2>/dev/null || true)"
  if [[ "${checksum_entry}" != "${artifact_checksum}" ]]; then
    fail_certificate "${platform} checksums.sha256 must match manifest checksum for ${artifact_name}"
  fi

  require_env_key "${metadata}" "CTX_RELEASE_SCHEMA_VERSION" "1"
  require_env_key "${metadata}" "CTX_RELEASE_CHANNEL" "dry-run"
  require_env_sha256 "${metadata}" "CTX_RELEASE_SHA256_${platform_key}"
  metadata_artifact="$(env_value "${metadata}" "CTX_RELEASE_ARTIFACT_${platform_key}")"
  metadata_checksum="$(env_value "${metadata}" "CTX_RELEASE_SHA256_${platform_key}")"
  if [[ "${metadata_artifact}" != "${artifact_name}" ]]; then
    fail_certificate "${platform} metadata artifact ${metadata_artifact:-<missing>} must equal manifest artifact name ${artifact_name:-<missing>}"
  fi
  if [[ "${metadata_checksum}" != "${artifact_checksum}" ]]; then
    fail_certificate "${platform} metadata checksum must equal manifest artifact checksum"
  fi

  artifact_full_path="${completion_evidence_root}/${artifact_path}"
  if [[ -f "${artifact_full_path}" ]]; then
    file_checksum="$(sha256_file "${artifact_full_path}")"
    if [[ "${file_checksum}" != "${artifact_checksum}" ]]; then
      fail_certificate "${platform} artifact file checksum must equal manifest checksum"
    fi
    file_bytes="$(wc -c < "${artifact_full_path}" | tr -d '[:space:]')"
    if [[ "${file_bytes}" != "${artifact_bytes}" ]]; then
      fail_certificate "${platform} artifact file size must equal manifest bytes"
    fi
  fi
}

validate_release_candidate_metadata() {
  local manifest="artifacts/buildkite/release-candidate/release-candidate-manifest.json"
  local metadata="artifacts/buildkite/release-candidate/ctx-release-metadata.env"
  local checksums="artifacts/buildkite/release-candidate/checksums.sha256"
  local plan="artifacts/buildkite/release-candidate/r2-upload-plan.md"
  local commands="artifacts/buildkite/release-candidate/r2-upload-commands.sh"
  local platform platform_key artifact checksum checksum_entry artifact_path actual_checksum r2_prefix public_base_url

  require_file "${manifest}"
  require_file "${metadata}"
  require_file "${checksums}"
  require_file "${plan}"
  require_file "${commands}"
  require_json_parser || return 0

  require_manifest_value "${manifest}" ".schema_version" "1" "release candidate manifest records schema version"
  require_manifest_value "${manifest}" ".kind" "ctx_release_candidate" "release candidate manifest records kind"
  require_manifest_value "${manifest}" ".release_candidate_status" "staging_plan_only" "release candidate manifest records staging-plan-only status"
  require_manifest_value "${manifest}" ".launch_ready" "false" "release candidate manifest records launch-blocked status"
  require_manifest_value "${manifest}" ".publishing" "false" "release candidate manifest records non-publishing status"
  require_manifest_value "${manifest}" ".package" "ctx" "release candidate manifest records package"
  require_manifest_value "${manifest}" ".version" "0.1.0" "release candidate manifest records 0.1.0"
  require_manifest_value "${manifest}" ".channel" "release-candidate" "release candidate manifest records channel"
  require_manifest_current_head "${manifest}" "release candidate manifest records current head"
  require_manifest_value "${manifest}" ".r2.bucket" "$(env_value "${metadata}" CTX_RELEASE_R2_BUCKET)" "release candidate manifest records R2 bucket"
  require_manifest_value "${manifest}" ".r2.prefix" "$(env_value "${metadata}" CTX_RELEASE_R2_PREFIX)" "release candidate manifest records R2 prefix"
  require_manifest_value "${manifest}" ".r2.upload_performed" "false" "release candidate manifest records R2 upload not performed"

  require_env_key "${metadata}" "CTX_RELEASE_SCHEMA_VERSION" "1"
  require_env_key "${metadata}" "CTX_RELEASE_VERSION" "0.1.0"
  require_env_key "${metadata}" "CTX_RELEASE_CHANNEL" "release-candidate"
  require_env_https "${metadata}" "CTX_RELEASE_BASE_URL"
  require_env_present "${metadata}" "CTX_RELEASE_R2_BUCKET" "release candidate metadata records R2 bucket"
  require_env_present "${metadata}" "CTX_RELEASE_R2_PREFIX" "release candidate metadata records R2 prefix"
  r2_prefix="$(env_value "${metadata}" CTX_RELEASE_R2_PREFIX)"
  public_base_url="$(env_value "${metadata}" CTX_RELEASE_BASE_URL)"
  if [[ "${r2_prefix}" != ctx/records/* ]]; then
    fail_certificate "release candidate R2 prefix must use ctx/records public artifact layout"
  fi
  if [[ "${r2_prefix}" == *work-recorder* || "${r2_prefix}" == *work-record* ]]; then
    fail_certificate "release candidate R2 prefix must not brand public artifact paths around work-record"
  fi
  if [[ "${public_base_url}" != */ctx/records/* ]]; then
    fail_certificate "release candidate public base URL must use ctx/records artifact layout"
  fi
  if [[ "${public_base_url}" == *work-recorder* || "${public_base_url}" == *work-record* ]]; then
    fail_certificate "release candidate public base URL must not brand public artifact URLs around work-record"
  fi

  while IFS='|' read -r platform platform_key; do
    artifact="$(env_value "${metadata}" "CTX_RELEASE_ARTIFACT_${platform_key}")"
    checksum="$(env_value "${metadata}" "CTX_RELEASE_SHA256_${platform_key}")"
    require_env_sha256 "${metadata}" "CTX_RELEASE_SHA256_${platform_key}"
    if [[ -z "${artifact}" || "${artifact}" = /* || "${artifact}" == *..* || "${artifact}" == */* || "${artifact}" == *\\* ]]; then
      fail_certificate "release candidate metadata artifact for ${platform} must be a safe file name"
      continue
    fi

    checksum_entry="$(awk -v name="${artifact}" '
      {
        checksum = $1
        artifact_name = $2
        sub(/\r$/, "", checksum)
        sub(/\r$/, "", artifact_name)
        if (artifact_name == name) {
          print checksum
          found = 1
          exit
        }
      }
      END { if (!found) exit 1 }
    ' "${completion_evidence_root}/${checksums}" 2>/dev/null || true)"
    if [[ "${checksum_entry}" != "${checksum}" ]]; then
      fail_certificate "release candidate checksums.sha256 must match metadata checksum for ${artifact}"
    fi

    artifact_path="artifacts/buildkite/release-dry-run/${platform}/${artifact}"
    require_file "${artifact_path}"
    if [[ -f "${completion_evidence_root}/${artifact_path}" ]]; then
      actual_checksum="$(sha256_file "${completion_evidence_root}/${artifact_path}")"
      if [[ "${actual_checksum}" != "${checksum}" ]]; then
        fail_certificate "release candidate metadata checksum must match artifact file for ${artifact}"
      fi
    fi
    require_env_present "${metadata}" "CTX_RELEASE_R2_OBJECT_${platform_key}" "release candidate metadata records R2 object for ${platform}"
  done <<'EOF'
linux-x64|linux_x64
macos-arm64|macos_arm64
macos-x64|macos_x64
windows-x64|windows_x64
EOF

  require_contains "${plan}" "Cleanup staged objects" "release candidate R2 plan records cleanup"
  require_contains "${commands}" "wrangler r2 object put" "release candidate R2 command file records staging commands"
  require_contains "${commands}" 'scripts/install.sh' "release candidate R2 command file stages Bash installer"
  require_contains "${commands}" 'scripts/install.ps1' "release candidate R2 command file stages PowerShell installer"
  require_contains "${manifest}" '"installers"' "release candidate manifest records installers"
  require_contains "${metadata}" "CTX_RELEASE_BLOCKER_FREEBSD_X64=" "release candidate metadata records FreeBSD blocker"
}

validate_provider_live_e2e_lanes() {
  local manifest="artifacts/buildkite/provider-live-e2e-lanes/provider-live-e2e-lanes.json"
  local notes="artifacts/buildkite/provider-live-e2e-lanes/provider-live-e2e-lanes.md"

  require_file "${manifest}"
  require_file "${notes}"
  require_json_parser || return 0

  require_manifest_value "${manifest}" ".schema_version" "1" "provider live E2E lanes record schema version"
  require_manifest_value "${manifest}" ".kind" "provider_live_e2e_lane_definitions" "provider live E2E lanes record kind"
  require_manifest_value "${manifest}" ".publishing" "false" "provider live E2E lanes record non-publishing status"
  require_manifest_value "${manifest}" ".default_enabled" "false" "provider live E2E lanes are disabled by default"
  require_manifest_current_head "${manifest}" "provider live E2E lanes record current head"
  require_contains "${notes}" "CTX_LIVE_PROVIDER_E2E=1" "provider live E2E notes record global opt-in"
  require_contains "${notes}" "Codex" "provider live E2E notes include Codex"
  require_contains "${notes}" "Claude Code" "provider live E2E notes include Claude Code"
  require_contains "${notes}" "Gemini CLI" "provider live E2E notes include Gemini CLI"
}

validate_dashboard_visual_evidence() {
  local manifest="artifacts/buildkite/finished-product/dashboard-report-artifact-review/visual-evidence.json"
  local status blocker screenshot_path

  require_file "${manifest}"
  require_file "artifacts/buildkite/finished-product/dashboard-report-artifact-review/screenshot-status.txt"
  require_json_parser || return 0

  require_manifest_value "${manifest}" ".schema_version" "1" "dashboard visual evidence records schema version"
  require_manifest_value "${manifest}" ".kind" "dashboard_visual_evidence" "dashboard visual evidence records kind"
  status="$(manifest_value "${manifest}" ".visual_status")"
  case "${status}" in
    captured)
      require_manifest_value "${manifest}" ".screenshot_count" "6" "dashboard visual evidence records screenshot count"
      for key in desktop_overview desktop_providers desktop_evidence mobile_overview mobile_providers mobile_evidence; do
        screenshot_path="$(manifest_value "${manifest}" ".${key}")"
        if [[ -z "${screenshot_path}" || "${screenshot_path}" = /* || "${screenshot_path}" == *..* ]]; then
          fail_certificate "dashboard visual evidence ${key} must be a safe relative screenshot path"
        else
          require_file "artifacts/buildkite/finished-product/dashboard-report-artifact-review/${screenshot_path}"
        fi
      done
      ;;
    accepted_blocker)
      blocker="$(manifest_value "${manifest}" ".accepted_visual_blocker")"
      if [[ -z "${blocker}" ]]; then
        fail_certificate "dashboard visual evidence accepted_blocker must include accepted_visual_blocker"
      fi
      require_contains \
        "artifacts/buildkite/finished-product/dashboard-report-artifact-review/screenshot-status.txt" \
        "accepted visual blocker:" \
        "dashboard visual evidence records explicit accepted blocker"
      ;;
    *)
      fail_certificate "dashboard visual evidence must be captured or accepted_blocker, got ${status:-<missing>}"
      ;;
  esac
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
  require_file "artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json"
  require_manifest_value "artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json" ".schema_version" "1" "FreeBSD blocker records schema version"
  require_manifest_value "artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json" ".kind" "release_platform_blocker" "FreeBSD blocker records kind"
  require_manifest_value "artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json" ".platform" "freebsd-x64" "FreeBSD blocker records platform"
  require_manifest_value "artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json" ".target_triple" "x86_64-unknown-freebsd" "FreeBSD blocker records target triple"
  require_manifest_value "artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json" ".publishing" "false" "FreeBSD blocker records non-publishing status"
  require_manifest_current_head "artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json" "FreeBSD blocker records current head"
  validate_release_candidate_metadata
  require_summary_status "artifacts/buildkite/r2-staging-smoke/r2-staging-smoke.json" "r2-staging-smoke"
  require_manifest_value "artifacts/buildkite/r2-staging-smoke/r2-staging-smoke.json" ".kind" "ctx_r2_staging_smoke" "R2 staging smoke records kind"
  require_manifest_value "artifacts/buildkite/r2-staging-smoke/r2-staging-smoke.json" ".upload_performed" "false" "R2 staging smoke records non-uploading CI posture"
  require_manifest_value "artifacts/buildkite/r2-staging-smoke/r2-staging-smoke.json" ".no_ctx_rs_cutover" "true" "R2 staging smoke records no ctx.rs cutover"
  require_manifest_value "artifacts/buildkite/r2-staging-smoke/r2-staging-smoke.json" ".validated_upload_object_count" "9" "R2 staging smoke validates upload object count"
  require_contains "artifacts/buildkite/r2-staging-smoke/r2-staging-smoke.md" "R2 object upload and public HTTPS smoke require approved credentials" "R2 staging smoke records upload blocker"
  require_summary_status "artifacts/buildkite/finished-product/product-decisions/product-decisions.json" "product-decisions"
  require_summary_status "artifacts/buildkite/finished-product/provider-fixtures/provider-fixtures.json" "provider-fixtures"
  validate_provider_live_e2e_lanes
  require_summary_status "artifacts/buildkite/finished-product/rich-search-context/rich-search-context.json" "rich-search-context"
  require_file "artifacts/buildkite/finished-product/rich-search-context/rich-context.json"
  require_summary_status "artifacts/buildkite/finished-product/dashboard-report-artifact-review/dashboard-report-artifact-review.json" "dashboard-report-artifact-review"
  require_contains "artifacts/buildkite/finished-product/dashboard-report-artifact-review/report.json" '"record_count"' "dashboard/report artifact records report data"
  validate_dashboard_visual_evidence
  require_summary_status "artifacts/buildkite/finished-product/pr-publish-dry-run/pr-publish-dry-run.json" "pr-publish-dry-run"
  require_contains "artifacts/buildkite/finished-product/pr-publish-dry-run/pr-comment-dry-run.md" "ctx-records:pr-comment:start" "PR publish artifact records dry-run marker"
  require_summary_status "artifacts/buildkite/finished-product/security-archive-fixtures/security-archive-fixtures.json" "security-archive-fixtures"
  require_contains "artifacts/buildkite/finished-product/security-archive-fixtures/security-archive-fixtures.md" "Publishing: false" "security archive fixture records non-publishing status"
  require_summary_status "artifacts/buildkite/finished-product/jj-e2e-blocker-status/jj-e2e-blocker-status.json" "jj-e2e-blocker-status"
  require_file "artifacts/buildkite/finished-product/jj-e2e-blocker-status/jj-e2e-blocker-status.txt"
  require_summary_status "artifacts/buildkite/finished-product/installer-dry-run-smoke/installer-dry-run-smoke.json" "installer-dry-run-smoke"
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
  markdown="${out_dir}/ctx-completion-certificate.md"
  json="${out_dir}/ctx-completion-certificate.json"
  generated_at="$(date +%s)"
  commit="$(git rev-parse HEAD)"
  branch="$(git branch --show-current)"
  build_url="${BUILDKITE_BUILD_URL:-local}"

  cat > "${markdown}" <<EOF
# ctx Completion Certificate

- Schema version: \`1\`
- Program: \`ctx-records-release-candidate\`
- Release candidate status: \`blocked-staging-plan-only\`
- Launch ready: \`false\`
- Evidence verification scope: \`non-publishing CI scaffolding and blocker evidence only\`
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
- Release candidate metadata: \`artifacts/buildkite/release-candidate/ctx-release-metadata.env\`
- Release candidate R2 upload plan: \`artifacts/buildkite/release-candidate/r2-upload-plan.md\`
- R2 staging smoke artifact: \`artifacts/buildkite/r2-staging-smoke/r2-staging-smoke.json\`
- Product decision regression artifact: \`artifacts/buildkite/finished-product/product-decisions/product-decisions.json\`
- Provider fixture import artifact: \`artifacts/buildkite/finished-product/provider-fixtures/provider-fixtures.json\`
- Provider live E2E lane definitions: \`artifacts/buildkite/provider-live-e2e-lanes/provider-live-e2e-lanes.json\`
- Rich search/context artifact: \`artifacts/buildkite/finished-product/rich-search-context/rich-context.json\`
- Dashboard/report artifact review: \`artifacts/buildkite/finished-product/dashboard-report-artifact-review/report.json\`
- Dashboard visual evidence manifest: \`artifacts/buildkite/finished-product/dashboard-report-artifact-review/visual-evidence.json\`
- PR publish dry-run artifact: \`artifacts/buildkite/finished-product/pr-publish-dry-run/pr-comment-dry-run.md\`
- Security/malicious archive fixture artifact: \`artifacts/buildkite/finished-product/security-archive-fixtures/security-archive-fixtures.md\`
- jj e2e blocker status artifact: \`artifacts/buildkite/finished-product/jj-e2e-blocker-status/jj-e2e-blocker-status.txt\`
- Installer dry-run smoke artifact: \`artifacts/buildkite/finished-product/installer-dry-run-smoke/install-dry-run.txt\`
- Release install documentation: \`docs/release-install.md\`
- Release supply-chain documentation: \`docs/release-supply-chain.md\`
- Release R2 layout documentation: \`docs/release-r2-layout.md\`
- FreeBSD release worker notes: \`docs/freebsd-release-worker.md\`

## External Release Blockers

- This certificate is not a release approval and does not certify a real public RC until every blocker below is replaced by explicit PASS evidence.
- FreeBSD native release lane requires a documented native \`freebsd-x64\` Buildkite queue or a separately proven cross-build lane.
- R2 object upload and public HTTPS installer smoke require approved credentials and an explicit manager-run command; normal CI validates the staging plan only.
- Provider live E2E lanes are defined but remain opt-in; providers cannot be marked \`supported-live\` without real lane artifacts.
- Full jj e2e validation requires a runner image with \`jj\` installed; the CI lane records availability and blocker status without installing external tools.
- Production release publication requires final release metadata with non-placeholder SHA-256 checksums for every published artifact.
- Signing, notarization, SBOM publication, and provenance publication require configured external credentials and policy approval.
EOF

  cat > "${json}" <<EOF
{
  "schema_version": 1,
  "kind": "ctx_completion_certificate",
  "program": "ctx-records-release-candidate",
  "release_candidate_status": "blocked-staging-plan-only",
  "launch_ready": false,
  "release_approval": false,
  "evidence_verification_scope": "non-publishing CI scaffolding and blocker evidence only",
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
    "release_candidate_metadata": "artifacts/buildkite/release-candidate/ctx-release-metadata.env",
    "release_candidate_manifest": "artifacts/buildkite/release-candidate/release-candidate-manifest.json",
    "release_candidate_r2_upload_plan": "artifacts/buildkite/release-candidate/r2-upload-plan.md",
    "r2_staging_smoke": "artifacts/buildkite/r2-staging-smoke/r2-staging-smoke.json",
    "product_decision_regressions": "artifacts/buildkite/finished-product/product-decisions/product-decisions.json",
    "provider_fixture_import": "artifacts/buildkite/finished-product/provider-fixtures/provider-fixtures.json",
    "provider_live_e2e_lane_definitions": "artifacts/buildkite/provider-live-e2e-lanes/provider-live-e2e-lanes.json",
    "rich_search_context": "artifacts/buildkite/finished-product/rich-search-context/rich-context.json",
    "dashboard_report_artifact_review": "artifacts/buildkite/finished-product/dashboard-report-artifact-review/report.json",
    "dashboard_visual_evidence": "artifacts/buildkite/finished-product/dashboard-report-artifact-review/visual-evidence.json",
    "pr_publish_dry_run": "artifacts/buildkite/finished-product/pr-publish-dry-run/pr-comment-dry-run.md",
    "security_archive_fixtures": "artifacts/buildkite/finished-product/security-archive-fixtures/security-archive-fixtures.md",
    "jj_e2e_blocker_status": "artifacts/buildkite/finished-product/jj-e2e-blocker-status/jj-e2e-blocker-status.txt",
    "installer_dry_run_smoke": "artifacts/buildkite/finished-product/installer-dry-run-smoke/install-dry-run.txt",
    "release_install_docs": "docs/release-install.md",
    "release_supply_chain_docs": "docs/release-supply-chain.md",
    "release_r2_layout_docs": "docs/release-r2-layout.md",
    "freebsd_release_worker_notes": "docs/freebsd-release-worker.md"
  },
  "evidence_verified": false,
  "evidence_scaffold_verified": true,
  "external_release_blockers": [
    "This certificate is not a release approval and does not certify a real public RC until every blocker below is replaced by explicit PASS evidence.",
    "FreeBSD native release lane requires a documented native freebsd-x64 Buildkite queue or a separately proven cross-build lane.",
    "R2 object upload and public HTTPS installer smoke require approved credentials and an explicit manager-run command; normal CI validates the staging plan only.",
    "Provider live E2E lanes are defined but remain opt-in; providers cannot be marked supported-live without real lane artifacts.",
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

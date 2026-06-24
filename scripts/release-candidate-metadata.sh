#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci-common.sh
source "${script_dir}/ci-common.sh"

usage() {
  cat <<'USAGE'
usage: scripts/release-candidate-metadata.sh [RELEASE_DRY_RUN_ROOT] [FREEBSD_BLOCKER_JSON]

Assembles non-publishing 0.1.0 release-candidate installer metadata from
platform release dry-run artifacts. The output includes a combined installer
metadata env file, combined checksums, a release-candidate manifest, and an R2
staging upload plan. It never uploads, signs, installs, or publishes.

If the native FreeBSD artifact is not present, set
CTX_RELEASE_EXCEPTION_FREEBSD_X64 to a manager-approved exception JSON path or
pass a FreeBSD blocker JSON for contract fixture mode.
USAGE
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
  ' "${path}"
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

require_sha256() {
  local value="$1"
  local description="$2"

  if [[ ! "${value}" =~ ^[0-9a-f]{64}$ ]]; then
    printf '%s must be a lowercase SHA-256 digest: %s\n' "${description}" "${value}" >&2
    return 1
  fi
}

safe_artifact_name() {
  local artifact="$1"

  [[ -n "${artifact}" && "${artifact}" != *..* && "${artifact}" != */* && "${artifact}" != *\\* ]]
}

artifact_platforms() {
  printf '%s\n' \
    'linux-x64|linux_x64|x86_64-unknown-linux-gnu' \
    'macos-arm64|macos_arm64|aarch64-apple-darwin' \
    'macos-x64|macos_x64|x86_64-apple-darwin' \
    'windows-x64|windows_x64|x86_64-pc-windows-gnu' \
    'freebsd-x64|freebsd_x64|x86_64-unknown-freebsd'
}

write_candidate_metadata() {
  local release_root="$1"
  local freebsd_blocker="${2:-}"
  local out_dir="$3"
  local first_metadata version channel public_base_url bucket prefix commit branch generated_at
  local metadata_out checksums_out manifest_out plan_out commands_out
  local platform platform_key target metadata artifact checksum artifact_path actual_checksum bytes
  local artifact_names=()
  local artifact_checksums=()
  local artifact_platform_keys=()
  local artifact_platforms_list=()
  local artifact_targets=()
  local artifact_paths=()
  local artifact_bytes=()
  local installer_names=(install.sh install.ps1)
  local installer_sources=(scripts/install.sh scripts/install.ps1)
  local installer_checksums=()
  local installer_bytes=()
  local freebsd_exception="${CTX_RELEASE_EXCEPTION_FREEBSD_X64:-}"
  local freebsd_status="not_included"
  local freebsd_artifact=""
  local index

  first_metadata="${release_root}/linux-x64/ctx-release-metadata.env"
  if [[ ! -s "${first_metadata}" ]]; then
    printf 'required release dry-run metadata is missing: %s\n' "${first_metadata}" >&2
    return 1
  fi

  version="$(env_value "${first_metadata}" CTX_RELEASE_VERSION)"
  if [[ "${version}" != "0.1.0" ]]; then
    printf 'release candidate metadata expects ctx 0.1.0, got %s\n' "${version}" >&2
    return 1
  fi

  channel="${CTX_RELEASE_CHANNEL:-release-candidate}"
  commit="$(git rev-parse HEAD)"
  branch="$(git branch --show-current)"
  generated_at="$(date +%s)"
  bucket="${CTX_RELEASE_R2_BUCKET:-ctx-release-artifacts}"
  prefix="${CTX_RELEASE_R2_PREFIX:-ctx/releases/${channel}/v${version}/${commit}}"
  public_base_url="${CTX_RELEASE_PUBLIC_BASE_URL:-https://example.invalid/ctx/releases/${channel}/v${version}/${commit}}"

  [[ "${public_base_url}" == https://* ]] || {
    printf 'CTX_RELEASE_PUBLIC_BASE_URL must be HTTPS: %s\n' "${public_base_url}" >&2
    return 1
  }

  mkdir -p "${out_dir}"
  metadata_out="${out_dir}/ctx-release-metadata.env"
  checksums_out="${out_dir}/checksums.sha256"
  manifest_out="${out_dir}/release-candidate-manifest.json"
  plan_out="${out_dir}/r2-upload-plan.md"
  commands_out="${out_dir}/r2-upload-commands.sh"

  while IFS='|' read -r platform platform_key target; do
    metadata="${release_root}/${platform}/ctx-release-metadata.env"
    if [[ ! -s "${metadata}" ]]; then
      if [[ "${platform}" == "freebsd-x64" && -n "${freebsd_exception}" && -s "${freebsd_exception}" ]]; then
        freebsd_status="manager_exception"
        continue
      fi
      if [[ "${platform}" == "freebsd-x64" && -n "${freebsd_blocker}" && -s "${freebsd_blocker}" ]]; then
        freebsd_status="blocked"
        continue
      fi
      printf 'required release dry-run metadata is missing: %s\n' "${metadata}" >&2
      return 1
    fi
    artifact="$(env_value "${metadata}" "CTX_RELEASE_ARTIFACT_${platform_key}")"
    checksum="$(env_value "${metadata}" "CTX_RELEASE_SHA256_${platform_key}")"
    safe_artifact_name "${artifact}" || {
      printf 'unsafe artifact name in %s: %s\n' "${metadata}" "${artifact}" >&2
      return 1
    }
    require_sha256 "${checksum}" "${platform} checksum"
    artifact_path="${release_root}/${platform}/${artifact}"
    if [[ ! -s "${artifact_path}" ]]; then
      printf 'required release artifact is missing or empty: %s\n' "${artifact_path}" >&2
      return 1
    fi
    actual_checksum="$(sha256_file "${artifact_path}")"
    if [[ "${actual_checksum}" != "${checksum}" ]]; then
      printf 'checksum mismatch for %s: metadata %s, file %s\n' "${artifact_path}" "${checksum}" "${actual_checksum}" >&2
      return 1
    fi
    bytes="$(wc -c < "${artifact_path}" | tr -d '[:space:]')"

    artifact_names+=("${artifact}")
    artifact_checksums+=("${checksum}")
    artifact_platform_keys+=("${platform_key}")
    artifact_platforms_list+=("${platform}")
    artifact_targets+=("${target}")
    artifact_paths+=("${artifact_path}")
    artifact_bytes+=("${bytes}")
    if [[ "${platform}" == "freebsd-x64" ]]; then
      freebsd_status="artifact_proof"
      freebsd_artifact="${artifact}"
    fi
  done < <(artifact_platforms)

  for index in "${!installer_sources[@]}"; do
    if [[ ! -s "${installer_sources[${index}]}" ]]; then
      printf 'required installer script is missing or empty: %s\n' "${installer_sources[${index}]}" >&2
      return 1
    fi
    installer_checksums+=("$(sha256_file "${installer_sources[${index}]}")")
    installer_bytes+=("$(wc -c < "${installer_sources[${index}]}" | tr -d '[:space:]')")
  done

  {
    printf '# ctx release installer metadata, schema v1.\n'
    printf '# Generated by scripts/release-candidate-metadata.sh from release dry-run artifacts.\n'
    printf '# Publishing remains disabled until manager approval and R2 upload smoke pass.\n'
    printf 'CTX_RELEASE_SCHEMA_VERSION=1\n'
    printf 'CTX_RELEASE_VERSION=%s\n' "${version}"
    printf 'CTX_RELEASE_CHANNEL=%s\n' "${channel}"
    printf 'CTX_RELEASE_BASE_URL=%s\n' "${public_base_url%/}"
    printf 'CTX_RELEASE_R2_BUCKET=%s\n' "${bucket}"
    printf 'CTX_RELEASE_R2_PREFIX=%s\n' "${prefix}"
    for index in "${!artifact_names[@]}"; do
      printf 'CTX_RELEASE_ARTIFACT_%s=%s\n' "${artifact_platform_keys[${index}]}" "${artifact_names[${index}]}"
      printf 'CTX_RELEASE_SHA256_%s=%s\n' "${artifact_platform_keys[${index}]}" "${artifact_checksums[${index}]}"
      printf 'CTX_RELEASE_R2_OBJECT_%s=%s/%s\n' "${artifact_platform_keys[${index}]}" "${prefix}" "${artifact_names[${index}]}"
    done
    printf 'CTX_RELEASE_INSTALLER_SH_R2_OBJECT=%s/install.sh\n' "${prefix}"
    printf 'CTX_RELEASE_INSTALLER_PS1_R2_OBJECT=%s/install.ps1\n' "${prefix}"
    if [[ "${freebsd_status}" == "blocked" ]]; then
      printf 'CTX_RELEASE_BLOCKER_FREEBSD_X64=%s\n' "${freebsd_blocker}"
    elif [[ "${freebsd_status}" == "manager_exception" ]]; then
      printf 'CTX_RELEASE_EXCEPTION_FREEBSD_X64=%s\n' "${freebsd_exception}"
    fi
  } > "${metadata_out}"

  : > "${checksums_out}"
  for index in "${!artifact_names[@]}"; do
    printf '%s  %s\n' "${artifact_checksums[${index}]}" "${artifact_names[${index}]}" >> "${checksums_out}"
  done

  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "kind": "ctx_release_candidate",\n'
    printf '  "release_candidate_status": "staging_plan_only",\n'
    printf '  "launch_ready": false,\n'
    printf '  "publishing": false,\n'
    printf '  "package": "ctx",\n'
    printf '  "version": "%s",\n' "$(ctx_json_escape "${version}")"
    printf '  "channel": "%s",\n' "$(ctx_json_escape "${channel}")"
    printf '  "git_commit": "%s",\n' "$(ctx_json_escape "${commit}")"
    printf '  "git_branch": "%s",\n' "$(ctx_json_escape "${branch}")"
    printf '  "generated_at_unix_s": %s,\n' "${generated_at}"
    printf '  "metadata": "artifacts/buildkite/release-candidate/ctx-release-metadata.env",\n'
    printf '  "checksums": "artifacts/buildkite/release-candidate/checksums.sha256",\n'
    printf '  "r2": {\n'
    printf '    "bucket": "%s",\n' "$(ctx_json_escape "${bucket}")"
    printf '    "prefix": "%s",\n' "$(ctx_json_escape "${prefix}")"
    printf '    "public_base_url": "%s",\n' "$(ctx_json_escape "${public_base_url%/}")"
    printf '    "upload_performed": false,\n'
    printf '    "metadata_object_key": "%s/ctx-release-metadata.env",\n' "$(ctx_json_escape "${prefix}")"
    printf '    "checksums_object_key": "%s/checksums.sha256",\n' "$(ctx_json_escape "${prefix}")"
    printf '    "manifest_object_key": "%s/release-candidate-manifest.json"\n' "$(ctx_json_escape "${prefix}")"
    printf '  },\n'
    printf '  "artifacts": [\n'
    for index in "${!artifact_names[@]}"; do
      if (( index > 0 )); then
        printf ',\n'
      fi
      printf '    {\n'
      printf '      "platform": "%s",\n' "$(ctx_json_escape "${artifact_platforms_list[${index}]}")"
      printf '      "platform_key": "%s",\n' "$(ctx_json_escape "${artifact_platform_keys[${index}]}")"
      printf '      "target_triple": "%s",\n' "$(ctx_json_escape "${artifact_targets[${index}]}")"
      printf '      "name": "%s",\n' "$(ctx_json_escape "${artifact_names[${index}]}")"
      printf '      "source_path": "%s",\n' "$(ctx_json_escape "${artifact_paths[${index}]}")"
      printf '      "sha256": "%s",\n' "$(ctx_json_escape "${artifact_checksums[${index}]}")"
      printf '      "bytes": %s,\n' "${artifact_bytes[${index}]}"
      printf '      "r2_object_key": "%s/%s"\n' "$(ctx_json_escape "${prefix}")" "$(ctx_json_escape "${artifact_names[${index}]}")"
      printf '    }'
    done
    printf '\n'
    printf '  ],\n'
    printf '  "installers": [\n'
    for index in "${!installer_names[@]}"; do
      if (( index > 0 )); then
        printf ',\n'
      fi
      printf '    {\n'
      printf '      "name": "%s",\n' "$(ctx_json_escape "${installer_names[${index}]}")"
      printf '      "source_path": "%s",\n' "$(ctx_json_escape "${installer_sources[${index}]}")"
      printf '      "sha256": "%s",\n' "$(ctx_json_escape "${installer_checksums[${index}]}")"
      printf '      "bytes": %s,\n' "${installer_bytes[${index}]}"
      printf '      "r2_object_key": "%s/%s"\n' "$(ctx_json_escape "${prefix}")" "$(ctx_json_escape "${installer_names[${index}]}")"
      printf '    }'
    done
    printf '\n'
    printf '  ],\n'
    if [[ "${freebsd_status}" == "artifact_proof" ]]; then
      printf '  "freebsd_x64": {\n'
      printf '    "status": "artifact_proof",\n'
      printf '    "required_release_target": true,\n'
      printf '    "target_triple": "x86_64-unknown-freebsd",\n'
      printf '    "artifact": "%s"\n' "$(ctx_json_escape "${freebsd_artifact}")"
      printf '  }\n'
    elif [[ "${freebsd_status}" == "blocked" ]]; then
      printf '  "freebsd_x64": {\n'
      printf '    "status": "blocked",\n'
      printf '    "required_release_target": true,\n'
      printf '    "target_triple": "x86_64-unknown-freebsd",\n'
      printf '    "blocker_artifact": "%s"\n' "$(ctx_json_escape "${freebsd_blocker}")"
      printf '  }\n'
    elif [[ "${freebsd_status}" == "manager_exception" ]]; then
      printf '  "freebsd_x64": {\n'
      printf '    "status": "manager_exception",\n'
      printf '    "required_release_target": true,\n'
      printf '    "target_triple": "x86_64-unknown-freebsd",\n'
      printf '    "exception_artifact": "%s"\n' "$(ctx_json_escape "${freebsd_exception}")"
      printf '  }\n'
    else
      printf '  "freebsd_x64": {\n'
      printf '    "status": "not_included",\n'
      printf '    "required_release_target": true,\n'
      printf '    "target_triple": "x86_64-unknown-freebsd",\n'
      printf '    "blocker_artifact": ""\n'
      printf '  }\n'
    fi
    printf '}\n'
  } > "${manifest_out}"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n\n'
    printf ': "${CTX_RELEASE_R2_BUCKET:=%s}"\n' "${bucket}"
    printf ': "${CTX_RELEASE_R2_PREFIX:=%s}"\n\n' "${prefix}"
    printf '# Requires Cloudflare Wrangler authenticated for the approved staging account.\n'
    printf '# These commands stage artifacts only; they do not repoint ctx.rs/install.\n'
    for index in "${!artifact_names[@]}"; do
      printf 'wrangler r2 object put "${CTX_RELEASE_R2_BUCKET}/${CTX_RELEASE_R2_PREFIX}/%s" --file "%s"\n' \
        "${artifact_names[${index}]}" \
        "${artifact_paths[${index}]}"
    done
    for index in "${!installer_names[@]}"; do
      printf 'wrangler r2 object put "${CTX_RELEASE_R2_BUCKET}/${CTX_RELEASE_R2_PREFIX}/%s" --file "%s"\n' \
        "${installer_names[${index}]}" \
        "${installer_sources[${index}]}"
    done
    printf 'wrangler r2 object put "${CTX_RELEASE_R2_BUCKET}/${CTX_RELEASE_R2_PREFIX}/ctx-release-metadata.env" --file "%s"\n' "${metadata_out}"
    printf 'wrangler r2 object put "${CTX_RELEASE_R2_BUCKET}/${CTX_RELEASE_R2_PREFIX}/checksums.sha256" --file "%s"\n' "${checksums_out}"
    printf 'wrangler r2 object put "${CTX_RELEASE_R2_BUCKET}/${CTX_RELEASE_R2_PREFIX}/release-candidate-manifest.json" --file "%s"\n' "${manifest_out}"
  } > "${commands_out}"
  chmod +x "${commands_out}"

  {
    printf '# R2 Release Candidate Upload Plan\n\n'
    printf '%s\n' '- Publishing: false'
    printf '%s `%s`\n' '- Version:' "${version}"
    printf '%s `%s`\n' '- Channel:' "${channel}"
    printf '%s `%s`\n' '- Bucket:' "${bucket}"
    printf '%s `%s`\n' '- Prefix:' "${prefix}"
    printf '%s `%s`\n\n' '- Public base URL for installer metadata:' "${public_base_url%/}"
    printf 'Stage with:\n\n'
    printf '```bash\n'
    printf 'bash %s\n' "${commands_out}"
    printf '```\n\n'
    printf 'Cleanup staged objects with:\n\n'
    printf '```bash\n'
    for index in "${!artifact_names[@]}"; do
      printf 'wrangler r2 object delete "%s/%s/%s"\n' "${bucket}" "${prefix}" "${artifact_names[${index}]}"
    done
    for index in "${!installer_names[@]}"; do
      printf 'wrangler r2 object delete "%s/%s/%s"\n' "${bucket}" "${prefix}" "${installer_names[${index}]}"
    done
    printf 'wrangler r2 object delete "%s/%s/ctx-release-metadata.env"\n' "${bucket}" "${prefix}"
    printf 'wrangler r2 object delete "%s/%s/checksums.sha256"\n' "${bucket}" "${prefix}"
    printf 'wrangler r2 object delete "%s/%s/release-candidate-manifest.json"\n' "${bucket}" "${prefix}"
    printf '```\n\n'
    printf 'After upload, run installer dry-runs against the approved HTTPS base URL before any ctx.rs/install cutover.\n'
  } > "${plan_out}"

  printf 'release candidate metadata: %s\n' "${metadata_out}"
  printf 'release candidate checksums: %s\n' "${checksums_out}"
  printf 'release candidate manifest: %s\n' "${manifest_out}"
  printf 'release candidate R2 plan: %s\n' "${plan_out}"
  printf 'release candidate R2 commands: %s\n' "${commands_out}"
}

main() {
  local release_root="${1:-artifacts/buildkite/release-dry-run}"
  local freebsd_blocker="${2:-artifacts/buildkite/release-blockers/freebsd-x64/freebsd-x64-blocker.json}"

  cd "${CTX_REPO_ROOT}"
  CTX_ARTIFACT_DIR="${CTX_ARTIFACT_DIR:-target/ctx-artifacts/release-candidate}"
  ctx_timing_init
  trap ctx_timing_finish EXIT

  case "${release_root}" in
    -h|--help|help)
      usage
      return 0
      ;;
  esac

  ctx_run_timed "release-candidate-metadata" write_candidate_metadata "${release_root}" "${freebsd_blocker}" "${CTX_ARTIFACT_DIR}"
}

main "$@"

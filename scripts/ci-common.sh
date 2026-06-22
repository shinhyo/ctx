#!/usr/bin/env bash

ctx_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX_REPO_ROOT="${CTX_REPO_ROOT:-$(cd "${ctx_script_dir}/.." && pwd)}"

ctx_positive_int() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && (( "$1" > 0 ))
}

ctx_detect_cpu_count() {
  local cores

  if [[ -r /proc/cpuinfo ]]; then
    cores="$(awk '
      /^physical id[[:space:]]*:/ { physical = $NF }
      /^core id[[:space:]]*:/ {
        if (physical != "") {
          seen[physical ":" $NF] = 1
        }
      }
      END {
        for (core in seen) {
          count++
        }
        if (count > 0) {
          print count
        }
      }
    ' /proc/cpuinfo)"
    if ctx_positive_int "${cores}"; then
      printf '%s\n' "${cores}"
      return 0
    fi
  fi

  cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  if ctx_positive_int "${cores}"; then
    printf '%s\n' "${cores}"
    return 0
  fi

  cores="$(sysctl -n hw.physicalcpu 2>/dev/null || true)"
  if ctx_positive_int "${cores}"; then
    printf '%s\n' "${cores}"
    return 0
  fi

  cores="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  if ctx_positive_int "${cores}"; then
    printf '%s\n' "${cores}"
    return 0
  fi

  if ctx_positive_int "${NUMBER_OF_PROCESSORS:-}"; then
    printf '%s\n' "${NUMBER_OF_PROCESSORS}"
    return 0
  fi

  printf '2\n'
}

ctx_detect_memory_gb() {
  local kb bytes gb

  if [[ -r /proc/meminfo ]]; then
    kb="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
    if ctx_positive_int "${kb}"; then
      gb=$(( kb / 1048576 ))
      if (( gb < 1 )); then
        gb=1
      fi
      printf '%s\n' "${gb}"
      return 0
    fi
  fi

  bytes="$(sysctl -n hw.memsize 2>/dev/null || true)"
  if ctx_positive_int "${bytes}"; then
    gb=$(( bytes / 1073741824 ))
    if (( gb < 1 )); then
      gb=1
    fi
    printf '%s\n' "${gb}"
    return 0
  fi

  printf '4\n'
}

ctx_init_resource_env() {
  local cpu_count memory_gb memory_jobs default_jobs bazel_ram_mb

  cpu_count="${CTX_CPU_COUNT:-$(ctx_detect_cpu_count)}"
  memory_gb="${CTX_TOTAL_MEMORY_GB:-$(ctx_detect_memory_gb)}"

  if ! ctx_positive_int "${cpu_count}"; then
    cpu_count=2
  fi
  if ! ctx_positive_int "${memory_gb}"; then
    memory_gb=4
  fi

  memory_jobs=$(( memory_gb / 3 ))
  if (( memory_jobs < 1 )); then
    memory_jobs=1
  fi

  default_jobs="${cpu_count}"
  if (( memory_jobs < default_jobs )); then
    default_jobs="${memory_jobs}"
  fi
  if (( default_jobs < 1 )); then
    default_jobs=1
  fi

  export CTX_CPU_COUNT="${cpu_count}"
  export CTX_TOTAL_MEMORY_GB="${memory_gb}"
  export TMPDIR="${TMPDIR:-${CTX_REPO_ROOT}/target/tmp}"
  export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-${CTX_CARGO_JOBS:-${default_jobs}}}"
  export RUST_TEST_THREADS="${RUST_TEST_THREADS:-${CTX_TEST_THREADS:-${CARGO_BUILD_JOBS}}}"
  export CARGO_TERM_COLOR="${CARGO_TERM_COLOR:-always}"
  mkdir -p "${TMPDIR}"

  export BAZEL_JOBS="${BAZEL_JOBS:-${CARGO_BUILD_JOBS}}"
  export BAZEL_LOCAL_CPU_RESOURCES="${BAZEL_LOCAL_CPU_RESOURCES:-${BAZEL_JOBS}}"
  bazel_ram_mb=$(( memory_gb * 512 ))
  if (( bazel_ram_mb < 1024 )); then
    bazel_ram_mb=1024
  fi
  export BAZEL_LOCAL_RAM_RESOURCES="${BAZEL_LOCAL_RAM_RESOURCES:-${bazel_ram_mb}}"
}

ctx_print_resource_env() {
  printf 'resource limits: cpu=%s memory_gb=%s cargo_jobs=%s test_threads=%s bazel_jobs=%s bazel_ram_mb=%s tmpdir=%s\n' \
    "${CTX_CPU_COUNT}" \
    "${CTX_TOTAL_MEMORY_GB}" \
    "${CARGO_BUILD_JOBS}" \
    "${RUST_TEST_THREADS}" \
    "${BAZEL_JOBS}" \
    "${BAZEL_LOCAL_RAM_RESOURCES}" \
    "${TMPDIR}"
}

ctx_json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

ctx_timing_init() {
  CTX_ARTIFACT_DIR="${CTX_ARTIFACT_DIR:-target/ctx-artifacts/check}"
  CTX_TIMING_FILE="${CTX_TIMING_FILE:-${CTX_ARTIFACT_DIR}/timings.json}"
  CTX_TIMING_EVENTS="${CTX_TIMING_FILE}.events"
  mkdir -p "${CTX_ARTIFACT_DIR}" "$(dirname "${CTX_TIMING_FILE}")"
  : > "${CTX_TIMING_EVENTS}"
}

ctx_timing_finish() {
  if [[ -n "${CTX_TIMING_EVENTS:-}" && -f "${CTX_TIMING_EVENTS}" ]]; then
    {
      printf '[\n'
      awk 'NR == 1 { printf "  %s", $0; next } { printf ",\n  %s", $0 } END { if (NR > 0) printf "\n" }' "${CTX_TIMING_EVENTS}"
      printf ']\n'
    } > "${CTX_TIMING_FILE}"
    rm -f "${CTX_TIMING_EVENTS}"
    printf 'timing artifact: %s\n' "${CTX_TIMING_FILE}"
  fi
}

ctx_timing_record() {
  local name="$1"
  local status="$2"
  local started_at="$3"
  local ended_at="$4"
  local duration_s="$5"
  local exit_code="$6"
  local note="${7:-}"

  printf '{"name":"%s","status":"%s","started_at_unix_s":%s,"ended_at_unix_s":%s,"duration_s":%s,"exit_code":%s,"note":"%s"}\n' \
    "$(ctx_json_escape "${name}")" \
    "$(ctx_json_escape "${status}")" \
    "${started_at}" \
    "${ended_at}" \
    "${duration_s}" \
    "${exit_code}" \
    "$(ctx_json_escape "${note}")" >> "${CTX_TIMING_EVENTS}"
}

ctx_run_timed() {
  local name="$1"
  shift
  local started_at ended_at duration_s exit_code status command

  command="$*"
  started_at="$(date +%s)"
  printf '==> %s\n' "${name}"
  set +e
  "$@"
  exit_code=$?
  set -e
  ended_at="$(date +%s)"
  duration_s=$(( ended_at - started_at ))

  if (( exit_code == 0 )); then
    status="passed"
  else
    status="failed"
  fi

  ctx_timing_record "${name}" "${status}" "${started_at}" "${ended_at}" "${duration_s}" "${exit_code}" "${command}"
  return "${exit_code}"
}

ctx_record_skip() {
  local name="$1"
  local note="$2"
  local now

  now="$(date +%s)"
  printf '==> %s: skipped (%s)\n' "${name}" "${note}"
  ctx_timing_record "${name}" "skipped" "${now}" "${now}" "0" "0" "${note}"
}

ctx_find_bazel() {
  if command -v bazel >/dev/null 2>&1; then
    command -v bazel
    return 0
  fi
  if command -v bazelisk >/dev/null 2>&1; then
    command -v bazelisk
    return 0
  fi
  return 1
}

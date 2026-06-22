#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci-common.sh
source "${script_dir}/ci-common.sh"

usage() {
  cat <<'USAGE'
usage: scripts/check.sh [all|fmt|check|clippy|test|bazel]...

Runs resource-capped local checks sequentially. Defaults to "all".
Environment overrides:
  CARGO_BUILD_JOBS     Cargo build parallelism, default min(cpu, memory_gb / 3)
  RUST_TEST_THREADS    Rust test threads, default CARGO_BUILD_JOBS
  BAZEL_JOBS           Bazel job count, default CARGO_BUILD_JOBS
  CTX_ARTIFACT_DIR     Timing artifact directory, default target/ctx-artifacts/check
  CLIPPY_FLAGS         Extra clippy flags, default "-D warnings"
USAGE
}

cargo_locked_args=()

setup_cargo_args() {
  cargo_locked_args=()
  if [[ "${CTX_CARGO_LOCKED:-1}" != "0" && -f Cargo.lock ]]; then
    cargo_locked_args+=(--locked)
  fi
}

run_fmt() {
  cargo fmt --all -- --check
}

run_check() {
  cargo check --workspace --all-targets "${cargo_locked_args[@]}"
}

run_clippy() {
  if [[ -n "${CLIPPY_FLAGS:-}" ]]; then
    cargo clippy --workspace --all-targets "${cargo_locked_args[@]}" -- ${CLIPPY_FLAGS}
  else
    cargo clippy --workspace --all-targets "${cargo_locked_args[@]}" -- -D warnings
  fi
}

run_test() {
  cargo test --workspace --all-targets "${cargo_locked_args[@]}" -- --test-threads "${RUST_TEST_THREADS}"
}

run_bazel() {
  local bazel_cmd="$1"

  "${bazel_cmd}" test \
    --jobs="${BAZEL_JOBS}" \
    --local_cpu_resources="${BAZEL_LOCAL_CPU_RESOURCES}" \
    --local_ram_resources="${BAZEL_LOCAL_RAM_RESOURCES}" \
    //...
}

run_mode() {
  local mode="$1"
  local bazel_cmd=""

  case "${mode}" in
    fmt)
      ctx_run_timed "cargo-fmt" run_fmt
      ;;
    check)
      ctx_run_timed "cargo-check" run_check
      ;;
    clippy)
      if ! cargo clippy --version >/dev/null 2>&1; then
        ctx_record_skip "cargo-clippy" "cargo clippy is not installed for this toolchain"
      else
        ctx_run_timed "cargo-clippy" run_clippy
      fi
      ;;
    test)
      ctx_run_timed "cargo-test" run_test
      ;;
    bazel)
      if [[ ! -f BUILD.bazel && ! -f MODULE.bazel && ! -f WORKSPACE && ! -f WORKSPACE.bazel ]]; then
        ctx_record_skip "bazel-test" "no Bazel workspace files found"
      elif ! bazel_cmd="$(ctx_find_bazel)"; then
        ctx_record_skip "bazel-test" "bazel/bazelisk is not installed"
      else
        ctx_run_timed "bazel-test" run_bazel "${bazel_cmd}"
      fi
      ;;
    all)
      run_mode fmt
      run_mode check
      run_mode clippy
      run_mode test
      run_mode bazel
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      printf 'unknown check mode: %s\n' "${mode}" >&2
      usage >&2
      return 2
      ;;
  esac
}

cd "${CTX_REPO_ROOT}"
ctx_init_resource_env
ctx_timing_init
trap ctx_timing_finish EXIT
ctx_print_resource_env
setup_cargo_args

if (( "$#" == 0 )); then
  set -- all
fi

for mode in "$@"; do
  run_mode "${mode}"
done

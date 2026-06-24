#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

if [[ -z "${HOME:-}" ]]; then
  export HOME="${repo_root}/target/bazel-home"
fi
mkdir -p "${HOME}"

# shellcheck source=scripts/ci-common.sh
source "${repo_root}/scripts/ci-common.sh"

ctx_init_resource_env
ctx_print_resource_env

bazel_bin="$(ctx_find_bazel)" || {
  printf 'bazel or bazelisk is required; set CTX_BOOTSTRAP_BAZELISK=1 to allow bootstrap\n' >&2
  exit 127
}

run_bazel() {
  printf '==> %s' "${bazel_bin}"
  printf ' %q' "$@"
  printf '\n'
  "${bazel_bin}" "$@"
}

if (( "$#" > 0 )); then
  run_bazel "$@"
  exit $?
fi

run_bazel query //...
run_bazel test //:presubmit --config=ci
run_bazel test //:production_hardening --config=ci
run_bazel test //:release_candidate --config=ci
run_bazel test //... --config=ci --test_tag_filters=-manual,-external

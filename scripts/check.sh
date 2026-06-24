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

bazel_bin=""

init_bazel() {
  if [[ -n "${bazel_bin}" ]]; then
    return 0
  fi

  ctx_init_resource_env
  ctx_print_resource_env

  bazel_bin="$(ctx_find_bazel)" || {
    printf 'bazel or bazelisk is required; set CTX_BOOTSTRAP_BAZELISK=1 to allow bootstrap\n' >&2
    exit 127
  }
}

run_bazel() {
  init_bazel
  printf '==> %s' "${bazel_bin}"
  printf ' %q' "$@"
  printf '\n'
  "${bazel_bin}" "$@"
}

usage() {
  cat <<'USAGE'
usage: scripts/check.sh [--mode MODE]
       scripts/check.sh --list-modes
       scripts/check.sh -- BAZEL_ARGS...

Modes:
  fast              fmt/check/docs/static contracts/package-fast
  presubmit         fast plus clippy, workspace tests, fresh-home, provider fixtures
  production        presubmit plus security/privacy/determinism/search smoke
  release-contract  production plus non-publishing release contract checks
  release_contract  same as release-contract
  release           release-contract plus real artifact evidence validation; fails until real platform artifacts, checksums, and install evidence are supplied
  ci                release-contract plus wildcard non-manual target detection (default)
  platform          host/platform smoke and blocker contracts
  provider-live     manual opt-in provider live E2E targets
  perf              manual search performance benchmark
  nightly           release-contract plus perf/provider-live manual lanes
  manual            current manual lanes: provider-live, perf, manual external
USAGE
}

list_modes() {
  printf '%s\n' \
    fast \
    presubmit \
    production \
    release-contract \
    release_contract \
    release \
    ci \
    platform \
    provider-live \
    perf \
    nightly \
    manual
}

mode="ci"

while (( "$#" > 0 )); do
  case "$1" in
    --mode=*)
      mode="${1#--mode=}"
      shift
      ;;
    --mode)
      shift
      if (( "$#" == 0 )); then
        printf 'missing value for --mode\n' >&2
        usage >&2
        exit 2
      fi
      mode="$1"
      shift
      ;;
    --list-modes)
      list_modes
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      if (( "$#" == 0 )); then
        printf 'missing Bazel arguments after --\n' >&2
        usage >&2
        exit 2
      fi
      run_bazel "$@"
      exit $?
      ;;
    *)
      run_bazel "$@"
      exit $?
      ;;
  esac
done

run_bazel query //...

case "${mode}" in
  fast)
    run_bazel test //:fast --config=ci
    ;;
  presubmit)
    run_bazel test //:presubmit --config=ci
    ;;
  production)
    run_bazel test //:production --config=ci
    ;;
  release-contract|release_contract)
    run_bazel test //:release_contract --config=ci
    ;;
  release)
    run_bazel test //:release --config=ci
    ;;
  ci)
    run_bazel test //:release_contract --config=ci
    run_bazel test //... --config=ci --test_tag_filters=-manual,-external,-provider-live,-perf
    ;;
  platform)
    run_bazel test //:platform --config=ci
    ;;
  provider-live)
    run_bazel test //:provider_live --config=ci
    ;;
  perf)
    run_bazel test //:perf --config=ci
    ;;
  nightly)
    run_bazel test //:nightly --config=ci
    ;;
  manual)
    run_bazel test //:manual --config=ci
    ;;
  *)
    printf 'unknown check mode: %s\n' "${mode}" >&2
    usage >&2
    exit 2
    ;;
esac

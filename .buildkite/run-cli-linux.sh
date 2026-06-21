#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
CTX_BIN="${REPO_ROOT}/bazel-bin/core/crates/ctx-http/ctx"

cd "${REPO_ROOT}"

".buildkite/run-bazel.sh" test //core/crates/ctx-http:ctx_cli_tests
".buildkite/run-bazel.sh" build //core/crates/ctx-http:ctx

test -x "${CTX_BIN}"
"${CTX_BIN}" --help >/dev/null

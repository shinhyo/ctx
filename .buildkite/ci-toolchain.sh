#!/usr/bin/env bash

ctx_ci_require_command() {
  local command_name="$1"
  local hint="${2:-}"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    if [[ -n "${hint}" ]]; then
      echo "error: required command '${command_name}' is missing from PATH. ${hint}" >&2
    else
      echo "error: required command '${command_name}' is missing from PATH" >&2
    fi
    exit 127
  fi
}

ctx_ci_bootstrap_node() {
  local node_version="${CTX_BUILDKITE_NODE_VERSION:-v20.19.5}"
  local platform=""
  case "$(uname -s)" in
    Linux)
      platform="linux"
      ;;
    Darwin)
      platform="darwin"
      ;;
    *)
      echo "error: unsupported OS for Node bootstrap: $(uname -s)" >&2
      exit 1
      ;;
  esac

  local machine=""
  machine="$(uname -m)"
  local node_arch=""
  case "${machine}" in
    x86_64|amd64)
      node_arch="x64"
      ;;
    arm64|aarch64)
      node_arch="arm64"
      ;;
    *)
      echo "error: unsupported machine architecture for Node bootstrap: ${machine}" >&2
      exit 1
      ;;
  esac

  local install_root="${HOME}/.local/node"
  local target_dir="${install_root}/${node_version}-${platform}-${node_arch}"
  local tarball=""
  local tar_extract_args=()
  case "${platform}" in
    linux)
      tarball="node-${node_version}-linux-${node_arch}.tar.xz"
      tar_extract_args=(-xJf)
      ;;
    darwin)
      tarball="node-${node_version}-darwin-${node_arch}.tar.gz"
      tar_extract_args=(-xzf)
      ;;
  esac

  if [[ ! -x "${target_dir}/bin/node" || ! -x "${target_dir}/bin/corepack" ]]; then
    ctx_ci_require_command curl "Node bootstrap requires curl."
    ctx_ci_require_command tar "Node bootstrap requires tar."
    mkdir -p "${install_root}"
    local tmpdir=""
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/ctx-buildkite-node.XXXXXX")"
    local download_url="https://nodejs.org/dist/${node_version}/${tarball}"
    curl -fsSL "${download_url}" -o "${tmpdir}/${tarball}"
    mkdir -p "${target_dir}"
    tar "${tar_extract_args[@]}" "${tmpdir}/${tarball}" -C "${tmpdir}"
    cp -R "${tmpdir}/node-${node_version}-${platform}-${node_arch}/." "${target_dir}/"
    rm -rf "${tmpdir}"
  fi

  export PATH="${target_dir}/bin:${PATH}"
}

CTX_CI_PNPM_CMD=()

ctx_ci_resolve_pnpm() {
  if (( ${#CTX_CI_PNPM_CMD[@]} > 0 )); then
    return 0
  fi

  if command -v pnpm >/dev/null 2>&1; then
    CTX_CI_PNPM_CMD=(pnpm)
    return 0
  fi

  if ! command -v node >/dev/null 2>&1 || ! command -v corepack >/dev/null 2>&1; then
    ctx_ci_bootstrap_node
  fi
  ctx_ci_require_command node "Node bootstrap failed; verify network access to nodejs.org."
  ctx_ci_require_command corepack "Use a Node.js distribution that includes Corepack."

  export COREPACK_DEFAULT_TO_LATEST="${COREPACK_DEFAULT_TO_LATEST:-0}"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT="${COREPACK_ENABLE_DOWNLOAD_PROMPT:-0}"
  export COREPACK_HOME="${COREPACK_HOME:-${HOME}/.cache/corepack}"
  mkdir -p "${COREPACK_HOME}"

  corepack prepare "${CTX_CI_PNPM_PACKAGE_MANAGER:-pnpm@9.15.1}" --activate >/dev/null
  CTX_CI_PNPM_CMD=(corepack pnpm)
}

ctx_ci_pnpm() {
  ctx_ci_resolve_pnpm
  "${CTX_CI_PNPM_CMD[@]}" "$@"
}

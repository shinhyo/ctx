#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci-common.sh
source "${script_dir}/ci-common.sh"

usage() {
  cat <<'USAGE'
usage: scripts/release-platform-blocker.sh freebsd-x64

Writes a non-publishing release-platform blocker artifact for a required target
that cannot be proven by the current Buildkite runner inventory.
USAGE
}

write_freebsd_blocker() {
  local out_dir="$1"
  local markdown json generated_at commit branch

  mkdir -p "${out_dir}"
  markdown="${out_dir}/freebsd-x64-blocker.md"
  json="${out_dir}/freebsd-x64-blocker.json"
  generated_at="$(date +%s)"
  commit="$(git rev-parse HEAD)"
  branch="$(git branch --show-current)"

  cat > "${markdown}" <<'EOF'
# FreeBSD x86_64 Release Blocker

- Platform: FreeBSD x86_64
- Required target triple: `x86_64-unknown-freebsd`
- Missing runner label: `queue=freebsd-x64`
- Attempted native command once the runner exists:
  `CTX_RELEASE_PLATFORM=freebsd-x64 CTX_RELEASE_TARGET_TRIPLE=x86_64-unknown-freebsd CTX_EXPECT_HOST_TRIPLE=x86_64-unknown-freebsd ./scripts/release-dry-run.sh`
- Exact blocker: this evidence tree does not contain native FreeBSD manifest,
  metadata, checksum, and binary artifacts from `queue=freebsd-x64`.
- Required Buildkite agent pool: a native FreeBSD x86_64 Buildkite agent pool
  tagged `queue=freebsd-x64` with Bash, Git, Rust stable, Cargo, and
  `sha256sum`, `shasum`, or FreeBSD `sha256` available.
- Artifact status: native FreeBSD release artifacts are missing from this
  evidence tree. A separate cross-build lane can only replace this after the
  FreeBSD linker/toolchain contract is proven and approved.
- Publishing status: this blocker step does not publish, upload, sign, or move
  any release channel.
EOF

  cat > "${json}" <<EOF
{
  "schema_version": 1,
  "kind": "release_platform_blocker",
  "platform": "freebsd-x64",
  "target_triple": "x86_64-unknown-freebsd",
  "missing_runner_label": "queue=freebsd-x64",
  "attempted_command": "CTX_RELEASE_PLATFORM=freebsd-x64 CTX_RELEASE_TARGET_TRIPLE=x86_64-unknown-freebsd CTX_EXPECT_HOST_TRIPLE=x86_64-unknown-freebsd ./scripts/release-dry-run.sh",
  "exact_blocker": "This evidence tree does not contain native FreeBSD manifest, metadata, checksum, and binary artifacts from queue=freebsd-x64.",
  "required_agent_pool": "Native FreeBSD x86_64 Buildkite agent pool tagged queue=freebsd-x64 with Bash, Git, Rust stable, Cargo, and sha256sum, shasum, or FreeBSD sha256 available.",
  "artifact_status": "Native FreeBSD release artifacts are missing from this evidence tree.",
  "publishing": false,
  "git_commit": "$(ctx_json_escape "${commit}")",
  "git_branch": "$(ctx_json_escape "${branch}")",
  "generated_at_unix_s": ${generated_at}
}
EOF

  printf 'release platform blocker: %s\n' "${markdown}"
  printf 'release platform blocker json: %s\n' "${json}"
}

main() {
  local platform="${1:-}"

  case "${platform}" in
    freebsd-x64)
      ;;
    -h|--help|help|"")
      usage
      return 0
      ;;
    *)
      printf 'unknown release platform blocker: %s\n' "${platform}" >&2
      usage >&2
      return 2
      ;;
  esac

  cd "${CTX_REPO_ROOT}"
  CTX_ARTIFACT_DIR="${CTX_ARTIFACT_DIR:-target/ctx-artifacts/release-platform-blocker}"
  ctx_timing_init
  trap ctx_timing_finish EXIT
  ctx_run_timed "release-platform-blocker-${platform}" write_freebsd_blocker "${CTX_ARTIFACT_DIR}"
}

main "$@"

# Work Record Productization Final Status

Date: 2026-06-20
Task: `feb64c1c-e58c-40f8-b1e9-1094dca0646e`
Branch: `ctx/agent-work-semantics-primary`
Worktree: `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/agent-work-semantics-primary`
Validated implementation head before this follow-up: `3cf1951 Use Work-first public vocabulary`

## What landed

- Public README and docs were repositioned around Work records, with ADE framed
  as an optional local interface rather than the whole product.
- Local setup commands now cover workspace setup, scratch workspace setup,
  status, and uninstall flows through the `ctx` CLI.
- Local Work capture commands now cover command capture, pull request linking,
  notes, recent records, and schema discovery.
- User-local capture shims were hardened for ownership, symlink, data-root,
  PATH, stdin, and argv behavior.
- Pull request linking was made idempotent and resolves workspace context from
  the current working directory.
- The launcher gained a Scratch Workspace action.
- Black-box CLI smoke coverage and executable shim tests were added for the
  Work-first local workflow.
- Public vocabulary was cleaned up away from hosted control-plane positioning,
  while keeping compatibility names where schema paths and APIs require them.

## Validation

The implementation pass completed these local checks before this follow-up:

- `pnpm -C core/apps/web typecheck`
- `pnpm -C core/apps/web lint`
- `pnpm -C core/apps/web test`
- `pnpm -C core/apps/web build`
- `cargo fmt --manifest-path core/Cargo.toml --all -- --check`
- `scripts/dev/cargo-safe.sh test --manifest-path Cargo.toml -p ctx-http --bin ctx --locked agent_work_cli`
- `scripts/dev/cargo-safe.sh test --manifest-path Cargo.toml -p ctx-http --bin ctx --locked setup_cli`
- `scripts/dev/cargo-safe.sh build --manifest-path Cargo.toml -p ctx-http --bin ctx --locked`
- CLI smoke cases for root help, setup help, Work help, Work schema, and a local
  Work capture/link/note/recent flow.
- `git diff --check`
- Public wording scans for stale hosted-control-plane and provisional-branch
  copy.

This follow-up is intentionally narrow and should only need wording and diff
hygiene checks.

## Review status

- Product/docs review findings were addressed.
- CLI, capture, and security review findings were addressed.
- Data-model review findings were addressed.
- Test coverage review findings were addressed with focused CLI and shim
  coverage.
- Done-ness review passed after clarifying that remote Buildkite, Bazel, hosted
  services, PR creation, remote push, and release work were out of scope for
  this local pass.

## Accepted deferrals

- No hosted/team sync, billing, organization policy, hosted audit dashboards, or
  enterprise administration flows are included in the public repo pass.
- No remote push, PR, merge, canary, production release, or remote Buildkite run
  is included.
- Compatibility schema paths and API names such as `agent-work` remain where
  required; this pass does not attempt a broad namespace migration.
- The local capture path is useful review context, not a tamper-proof audit
  system.
- `ctx work link-pr` is URL-based today. Richer provider-specific PR discovery
  can be added later.
- Arbitrary executable UI/plugin runtime work remains deferred.
- Full workspace Rust and Bazel sweeps remain deferred on this host unless
  explicitly requested, because broad concurrent Rust builds previously caused
  severe local resource pressure. Focused Rust checks should continue to use the
  resource-safe wrapper.

# Work Recorder Productization Decision Log

Updated: 2026-06-22T17:39:00-05:00

## Decisions

- Use `ctxrs/ctx` branch `work-record` for public Work Recorder productization.
- Preserve the reviewed manager plan in this worktree before implementation.
- Treat `ctxrs/ade` as frozen unless a maintenance-only need is discovered.
- Avoid the dirty canonical `ctx-private` checkout; hosted/private work will use
  a separate manual `ctx-private` worktree after reading private repo
  instructions.
- Use a separate private hosted worktree:
  `/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx-private/work-recorder-hosted-team`
  on branch `ctx/work-recorder-hosted-team`.
- Sequence public local schema/storage before private hosted sync work, because
  hosted sync should follow the stabilized local JSON/schema contract.
- Prefer a new Work Recorder hosted worker/service in `ctx-private` rather than
  overloading the existing control-plane worker.

## Pending Decisions

- Exact public crate/module split after current-code mapper output.
- Whether any existing ADE surfaces are quarantined, hidden, or removed in this
  branch.
- Hosted staging environment choice and whether credentials allow deployment
  from this machine.
- Buildkite runner/platform availability and any required queue/pool changes.

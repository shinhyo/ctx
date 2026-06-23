# Work Recorder Productization Decision Log

Updated: 2026-06-22T20:02:05-05:00

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
- Public Work Record and evidence IDs use UUIDv7 for sortable local/offline IDs.
- Public CLI JSON responses use schema-versioned envelopes. `ctx context --json`
  emits the public `AgentContextPacket` instead of the older internal context
  shape.
- Current evidence writes must be attached to a Work Record. When
  `ctx evidence run` is invoked without `--record`, the CLI creates a command
  evidence Work Record and attaches the evidence automatically.
- Full command output is stored as content-addressed local-only artifacts under
  `blobs/`; evidence rows keep bounded redacted previews and artifact pointers.
- Archive JSON carries both `schema_version: 1` and the existing `version: 1`
  field so public JSON is consistently versioned without breaking current archive
  compatibility.
- Agent context output preserves `local_only` visibility by default. Records
  must be explicitly promoted before future reportable/team-sync surfaces expose
  richer content.
- Evidence stream artifacts are represented through `evidence_artifacts` so both
  stdout and stderr can be attached. The single `evidence.artifact_id` column is
  retained as a primary compatibility pointer.
- Archive import preflights evidence references and then imports records,
  evidence rows, artifact rows, and evidence/artifact links in one DB
  transaction.
- Public JSON archives include evidence artifact payloads so local-only full
  stdout/stderr content can survive export/import. This is explicit portability
  behavior, not a default report/share surface; exported archives must be
  reviewed before leaving the machine.
- Local dashboard export is static-by-default: no JavaScript, no remote assets,
  no publish/sync side effect, safe workspace labels instead of absolute local
  paths, and redacted command/evidence previews in default HTML.
- Public README/docs should describe dashboard export and Git/jj/gh wrapper
  shims as implemented local features, while keeping provider-native history
  import, shell/provider hooks, hosted sync, PR comment publishing, installer
  URLs, and `ctx publish` marked as not shipped.
- Normal Work Recorder commands import pending capture spool files on demand
  rather than requiring a daemon. Failed files remain local and inspectable, and
  `ctx repair` is the explicit retry path.
- Public Buildkite matrix wiring uses the known private queue inventory where
  appropriate: `main-linux`, `release-linux-managed`,
  `ctx-mac-gui-shared-arm64`, `ctx-mac-gui-shared-x64`, and `windows-x64`.
- Public release dry-runs are host-native and non-publishing. Each native lane
  sets `CTX_EXPECT_HOST_TRIPLE` and fails before artifact creation if Buildkite
  routes the job to the wrong Rust host triple.
- FreeBSD x86_64 is tracked as a documented release blocker instead of a weak
  cross-build claim because no native `queue=freebsd-x64` runner is documented
  yet and no FreeBSD linker/toolchain cross-build contract has been proven.
- The public pipeline owns a local `scripts/check-buildkite-pipeline.sh`
  contract check so required step keys, queues, host triples, and dry-run flags
  can be validated without Buildkite credentials.
- Hosted Work Record sync starts metadata-first. Raw transcripts, prompts,
  messages, stdout/stderr, and tool-output-like fields are rejected by the
  hosted worker until there is an explicit user/team policy for transcript sync.
- Hosted blobs are content-addressed by SHA-256 and uploaded explicitly to R2.
  The initial worker records blob manifests but does not infer transcript sync
  or publish public reports by default.

## Pending Decisions

- Exact public crate/module split after current-code mapper output.
- Whether any existing ADE surfaces are quarantined, hidden, or removed in this
  branch.
- Hosted staging deployment credentials and whether this machine can mutate
  Cloudflare/Neon/R2 directly.
- Live Buildkite runner/platform availability, Buildkite agent/API token access,
  and any required queue/pool changes after the public/private pipelines are
  attached to real runners.
- Whether legacy unattached evidence rows from pre-productization stores should
  be migrated into synthetic Work Records or only tolerated as legacy read data.

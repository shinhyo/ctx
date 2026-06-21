# Full Work Inspector And Capture Suite Plan

## Context

Task: `feb64c1c-e58c-40f8-b1e9-1094dca0646e`

Canonical branch:

`ctx/agent-work-semantics-primary`

Canonical worktree:

`/home/daddy/code/ctx-multi-repo-workspace/worktrees/ctx/agent-work-semantics-primary`

Current product state:

- Work record storage, reports, context, evidence, timeline, search, and
  Buildkite verification exist.
- Dogfood with five scratch runs proved Work records can be created and opened.
- Dogfood also proved the visible report is too thin: it is not yet a full
  inspector for transcript, commands, output, diffs, artifacts, evidence, and
  agent handoff.

## Goal

Build the first full Work Inspector and deterministic capture suite.

The product should let a human or fresh agent open one Work record and answer:

- what was the objective?
- what agent/session/task/run produced it?
- what transcript or conversation context is retained?
- what commands ran, with exit status and bounded output previews?
- what files/commits/PRs changed?
- what evidence exists and what is stale, missing, weak, or failed?
- what artifacts/screenshots/logs were produced?
- what should a reviewer or future agent do next?

Default surfaces must be redacted and share-safe. Raw/local-private surfaces may
exist, but only behind explicit local controls and clear labeling.

## Dispatch Shape

Implement this as phased slices under one end-to-end program. Do not treat the
whole plan as one vague implementation blob.

Required phases:

1. Work Inspector API/report v2 contract:
   - named typed route response fields for transcript, commands, changes,
     artifacts, evidence, timeline, context, trust, and share-safe raw JSON;
   - deterministic fixture data that can populate every inspector tab;
   - no UI reverse-engineering from compacted strings or arbitrary JSON.
2. Work Inspector UI:
   - standalone route using the v2 typed contract;
   - complete dashboard-style tabs from deterministic fixtures and real data;
   - visual tests and screenshot review.
3. ADE/session-to-Work projection:
   - deterministic Work IDs, link IDs, event IDs, sequence behavior, and
     backfill/trigger entry point;
   - transcript/tool/artifact session state projected into Work records.
4. Work artifact bridge:
   - safe artifact metadata, thumbnails/download links, allowed roots, and
     route-level checks.
5. Deterministic CLI capture refinement:
   - explicit evidence command output previews first;
   - git/gh allowlisted metadata/link capture;
   - shim stdout/stderr tee/spool capture only after a design is proven not to
     perturb command behavior.
6. Dogfood, screenshots, reviewer reconstruction, and CI.

The first useful milestone is not a renamed report page. It is a typed v2
contract plus a Work Inspector that shows real, non-empty, reconstructive content
in every relevant tab.

## Product Decision

This is not just a summary report.

Build a standalone Work Inspector route at the existing stable route:

`/workspaces/:id/work/:workId`

The inspector should replace or wrap the current `workReport` page. Do not embed
it inside the Workbench first. Later, Workbench task rows/session headers can add
"Open Work Inspector" links when they have a Work ID.

Use the existing repo UI stack:

- React/Vite;
- local shadcn-style primitives already configured in `components.json`;
- Radix primitives already in dependencies where useful;
- lucide icons;
- ctx CSS tokens and Workbench visual language.

Do not add a bulky dashboard dependency. Adapt shadcn dashboard/block layout
patterns manually into ctx components using existing tokens and styles.

## Capture Layers

### 1. ADE/Daemon Session Capture

This is the highest-fidelity path.

Implement an idempotent projector from existing ADE session state into Work
records:

- session/task/worktree creation creates or finds a Work record;
- session/task/worktree/run links become `WorkRecordLink`s;
- `SessionEvent`, `Message`, `SessionTurn`, and `SessionTurnTool` are projected
  to Work events;
- user messages, assistant messages, tool calls/results, reasoning summaries,
  artifacts, and subagent/session relations are preserved where available;
- source IDs are stable so repeated projection/backfill does not duplicate rows.

Concrete ID requirements:

- `work_id`: deterministic from workspace/task/session root where possible,
  otherwise generated once and linked to the session/task root.
- `link_id`: deterministic from `work_id`, target kind, target id, and link
  strength.
- `event_id`: deterministic from `work_id`, source kind, source id, and sequence.
- sequence: stable per Work record; backfill must preserve order and not reorder
  later live events unexpectedly.
- projection trigger: session/task creation plus an explicit backfill/rebuild
  command or route for existing sessions.

### 2. CLI Setup / Git And GitHub Capture

Keep friction low. Users should not need `ctx work begin` for normal usage.

Use `ctx setup workspace` as the opt-in point that installs deterministic
capture for the workspace:

- ctx-owned `git` and `gh` shims only for the first implementation;
- shims forward to the real tool first and preserve stdout, stderr, and exit
  status;
- shims strip the shim directory from `PATH` before invoking the real command;
- capture failure must not break the underlying command;
- successful allowlisted commands such as `git commit`, `git push`,
  `gh pr create`, `gh pr view`, and `gh pr status` create low-trust Work
  links/evidence when the outcome can be determined safely;
- explicitly denylist secret/auth/config commands such as `gh auth token`,
  auth flows, env/config dumping, and remotes with embedded credentials;
- PR and commit links are deterministic where possible, with agent-mediated
  `ctx work link-*` as fallback.

Do not shim arbitrary commands globally in this pass. For arbitrary commands,
keep and improve explicit:

`ctx work evidence <work-id> run -- <command>`

### 3. Command Output Capture

Command output should exist in the inspector, but safely.

Implement bounded, redacted command output previews for:

- explicit `ctx work evidence ... run -- ...`;
- future wrapper commands.

Large stdout/stderr should be stored as local-private artifacts/blobs with
digests and byte sizes. Default report/context/search surfaces should expose only
bounded redacted previews and metadata.

Do not index raw command output into search.

Do not require git/gh shim stdout/stderr capture in the first pass unless the
implementation includes a proven tee/spool design that preserves TTY behavior,
streaming, ordering, exit status, and failure isolation. Metadata/link capture
from git/gh shims is enough for this phase.

### 4. Artifact Capture

Bridge existing session artifacts into Work records:

- artifact links should become Work links/evidence where applicable;
- Work Inspector should resolve artifact metadata without requiring the user to
  know the session ID;
- screenshots/images should render as thumbnails when safe;
- logs/files should render as download/open links plus bounded previews.

Artifact paths must be canonicalized, workspace-contained, regular files only,
and symlink/path traversal safe.

Artifact serving requirements:

- define allowed artifact roots, including session artifact roots that may live
  outside the repo checkout;
- open files in a TOCTOU-resistant way where practical;
- MIME/content sniff before rendering;
- do not inline SVG or HTML as executable content;
- serve same-origin/authenticated artifact URLs;
- thumbnails must not expose raw local paths.

### 5. Optional Agent/LLM Layer

LLM-derived summaries are useful, but not the foundation.

Keep provider-backed LLM summary generation off by default in the public local
route slice. If implemented later:

- require explicit consent;
- record provider/model/provenance;
- record source material manifest;
- mark `source_material_left_machine=true`;
- keep generated summaries clearly labeled as model-derived;
- never treat LLM summaries as evidence.

## Work Inspector UI

Build a dashboard-style inspector page with a compact sticky header, metrics
strip, primary tab content, and a desktop right rail that collapses cleanly on
mobile.

Required components:

- `WorkInspectorPage`
- `useWorkInspectorReport`
- `WorkInspectorView`
- `WorkInspectorHeader`
- `TrustBanner`
- `InspectorMetricStrip`
- `InspectorTabs`
- `OverviewTab`
- `TranscriptTab`
- `CommandsTab`
- `EvidenceTab`
- `TimelineTab`
- `ChangesTab`
- `ArtifactsTab`
- `ContextTab`
- `RawRedactedJsonTab`

Required tab behavior:

- keyboard-accessible native ARIA tabs;
- stable layout with no horizontal overflow;
- no text overlap or clipping at desktop, tablet, and mobile widths;
- raw JSON collapsed by default;
- raw transcript/local-private output never shown by default.

Required content:

- Overview: objective, summary, lifecycle, branch, commits, PR links, trust,
  risks, recommended next action.
- Transcript: projected user/assistant/subagent/tool transcript when available,
  with raw availability/inclusion clearly labeled.
- Commands: command, cwd label, exit code, duration, source, trust, stdout/stderr
  redacted previews, output artifact links.
- Evidence: tests/builds/screenshots/reviews, status, freshness, fingerprint,
  source/fidelity/trust.
- Timeline: chronological event stream with type, actor/source, redaction class,
  and stable IDs.
- Changes: changed files, diff stats, commits, PRs, duplicate strong links.
- Artifacts: thumbnails/downloads for screenshots and structured artifact cards.
- Context: agent-handoff JSON preview and summary claims.
- Raw redacted JSON: report payload only after redaction; no raw payload JSON or
  raw transcript bodies.

The raw/redacted JSON tab must be a whitelist projection made from explicit
share-safe route fields. It must not recursively redact arbitrary raw-ish data.
It must not include `payload_json`, transcript bodies, raw stdout/stderr,
absolute paths, local artifact paths, or arbitrary `target_json` blobs.

## API / Data Requirements

Extend or add typed route responses so the page does not reverse-engineer
strings:

- report summary;
- paged timeline/events;
- transcript projection;
- command/evidence output previews;
- changed files/diff stats;
- artifact metadata and safe URLs;
- redacted context JSON;
- trust/freshness explanation.

Named response/model requirements:

- `WorkspaceWorkInspector`
- `WorkspaceWorkTranscriptItem`
- `WorkspaceWorkCommandPreview`
- `WorkspaceWorkChangeSummary`
- `WorkspaceWorkArtifactSummary`
- `WorkspaceWorkEvidenceSummary`
- `WorkspaceWorkTimelineItem`
- `WorkspaceWorkSafeJson`

The UI must not parse `redacted_text`, `output_ref`, `artifact_ref`, or generic
JSON to infer core fields.

Keep projections versioned and rebuildable. Preserve the distinction between:

- local-private raw store;
- redacted shareable projection;
- low-trust observed/shim capture;
- higher-fidelity ctx/ADE-admitted session capture.

## Privacy / Security Guardrails

Default Work Inspector views must not include:

- raw transcripts;
- raw `payload_json`;
- raw stdout/stderr;
- env vars;
- host roots or absolute paths;
- secrets/tokens;
- raw artifact contents.

All UI renders data as text, never stored HTML.

External URLs must be scheme-allowlisted. `javascript:`, `data:`, invalid URLs,
and unsafe PR/artifact links render as text, not anchors.

Search docs and FTS must not contain raw transcript or raw command output.

Privacy checks apply to every public/default surface:

- API route responses;
- DOM text;
- screenshots;
- search/FTS rows;
- exported report/context JSON;
- status files;
- agent-readable JSON;
- artifact thumbnails and links.

Add visible retention controls or at least documented CLI-backed deletion for:

- raw transcript purge;
- command-output purge;
- artifact purge;
- search-index rebuild.

## Testing Requirements

Backend/store/route tests:

- idempotent session-to-Work projection;
- command output preview redaction;
- no raw payload/transcript/output in default report/context/timeline/search;
- git/gh shim forwarding and exit-code preservation;
- shim capture failure does not break real command;
- symlink/path traversal artifact rejection;
- safe URL handling;
- failed-then-passed evidence remains conservative;
- client-submitted verified evidence is downgraded.

Frontend tests:

- Work Inspector renders every tab from deterministic fixture data;
- every dogfood-relevant tab has typed, non-empty content, not placeholders or
  compacted snippet strings;
- unsafe URLs render as text;
- long commands/paths/titles do not overflow;
- raw transcript unavailable/included states are clear;
- evidence states are visually and semantically distinct;
- artifacts render links/thumbnails where safe;
- ARIA tab keyboard navigation works.

Leak tests:

- fake `OPENAI_API_KEY`;
- bearer tokens;
- OAuth codes;
- `/home/...` paths;
- Windows drive paths and UNC paths;
- raw stdout/stderr;
- raw transcript bodies;
- HTML/script injection strings.

Visual tests:

- add Playwright visual spec for the Work Inspector;
- use existing visual helpers where available;
- screenshot light and dark mode;
- viewports: desktop, desktop-tight, narrow, mobile-narrow;
- states: verified, failed, stale, missing evidence, duplicate links, no evidence,
  long command/title, unsafe URL.

Subagents must visually inspect screenshots, not just rely on test pass/fail.

Visual review must fail if screenshots show:

- placeholder tabs where dogfood data exists;
- clipped command output;
- indistinct evidence states;
- missing expected artifact thumbnails;
- horizontal overflow;
- tab labels clipped or inaccessible on mobile.

## Dogfood / E2E Requirements

After implementation:

1. Run at least five scratch Work-record tasks again or reuse the existing five
   only if fresh captures exercise the new features.
2. Generate/open the new Work Inspector pages in Chrome.
3. Confirm each page has useful:
   - overview;
   - transcript/timeline;
   - commands/output previews;
   - evidence;
   - changes;
   - artifacts.
4. Have a fresh reviewer agent answer task-reconstruction questions using only
   the Work Inspector and redacted agent-readable JSON.

The final verdict should explicitly say whether the new inspector is good enough
for a fresh agent to catch up without adjacent scratch repo spelunking.

Hard reviewer gate:

- The fresh reviewer must reconstruct 5/5 runs.
- The rubric must include objective, producing session/task/run, key transcript
  context, exact commands and exit statuses, output-preview meaning,
  files/commits/PRs, evidence status/freshness, artifacts, and next action.
- The reviewer may not inspect adjacent scratch repos, raw transcript bodies,
  local artifact files, or implementation code.
- A miss is a blocker, not merely a recorded product gap.

## Validation / CI

Run targeted checks first, then broad checks:

- Rust/store/daemon/http focused tests for new Work APIs and capture;
- web unit tests for Work Inspector;
- Playwright visual Work Inspector tests;
- web typecheck/lint/build;
- Rust workspace tests/builds through resource-safe wrapper;
- Buildkite release-verification matrix if product code/config changes warrant
  it, especially if CI/build scripts or public shippable paths are touched.

## Documentation

Update docs to explain:

- what Work Inspector is;
- what ctx captures deterministically;
- what requires ADE session capture;
- what requires `ctx setup workspace`;
- what requires explicit `ctx work evidence run`;
- what is low-trust user-space shim context;
- what is not captured by magic;
- privacy/redaction/retention model;
- optional future LLM summaries.

## Finish Criteria

Do not declare done until all are true:

- Full Work Inspector exists at `/workspaces/:id/work/:workId`.
- ADE sessions can project transcript/tool/artifact events into Work records.
- `git`/`gh` setup capture links commits/PRs deterministically where possible.
- Explicit command evidence exposes redacted output previews in the inspector.
- The inspector shows transcript, commands, evidence, timeline, changes,
  artifacts, and context tabs.
- Default views pass leak tests and do not expose raw local-private material.
- Visual screenshots pass human/subagent review across required states/viewports.
- Five dogfood Work records open in Chrome and are materially more useful than
  the previous text-snippet report.
- Each dogfood record has typed, populated transcript/timeline, commands,
  changes, evidence, artifacts, context, and trust data where the underlying
  capture source produced that data.
- Fresh reviewer agent can reconstruct 5/5 runs from the inspector and redacted
  agent-readable JSON alone.
- Leak tests serialize every route response, inspect DOM text, inspect saved
  screenshots, query search/FTS, and scan the final status file.
- Tests and CI gates pass or blockers are concrete and justified.
- Status file records changed files, tests, screenshots, dogfood URLs, reviewer
  verdicts, known gaps, and final head.
- No merge, release, or announcement happens unless separately requested.

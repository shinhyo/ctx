**Local Work Records for coding agents.**

ctx is an explicit recorder for coding-agent work: prompts and notes you save with `ctx work record`, command evidence you run through `ctx work evidence run`, pull request URLs you attach with `ctx work link-pr`, and the local context you search, report, export, and import.

Coding agents are useful, but the useful review trail is easy to lose unless you record it deliberately. ctx stores what you or your agent send to the `ctx work ...` CLI, so a task can be reviewed, resumed, shared, or audited from a local record.

ctx is not trying to replace your agent. It works beside the agents and CLIs you already use, gives them a small durable place to write work history, and stores that history locally in SQLite first.

## Install

```bash
curl -fsSL https://ctx.rs/install | sh
```

Platform support: macOS and Linux today. Windows is planned.

- Website: https://ctx.rs
- Getting started: [docs/getting-started.md](docs/getting-started.md)
- Work model: [docs/work-model.md](docs/work-model.md)
- CLI reference: [docs/cli-reference.md](docs/cli-reference.md)
- Privacy and storage: [docs/privacy-storage.md](docs/privacy-storage.md)

## What ctx captures

- The original prompt, task brief, or follow-up note that shaped the work
- Command evidence captured by running tools through `ctx work evidence run`
- Exit codes, stdout, stderr, and duration for recorded evidence commands
- Pull request links attached to the work record
- Searchable notes, tags, workspace paths, and record kinds
- Importable and exportable JSON archives for local handoff or backup
- Context and reports that help a reviewer understand the saved record and evidence

## Why Work Records

- A code change needs context. The record keeps saved prompts, notes, command evidence, pull request links, and review context together.
- Useful agent output should be written into a durable record instead of living only in one terminal session or provider UI.
- Existing agents should keep working. ctx sits beside them instead of forcing a new harness.
- Local-first storage matters. Your records, command evidence, pull request links, and task metadata start on your machine.
- Review is easier when evidence is attached to the change instead of scattered through chat and shell history.

## How it works

ctx is CLI-first. Set up the local workspace, write a record, capture command evidence, and link the pull request that carries the change.

```bash
ctx workspace setup
ctx work record \
  --title "fix flaky checkout test" \
  --body "Reproduced the retry failure and captured the verification command." \
  --tag test --kind task --json
ctx work evidence run --record <record-id> cargo test -p checkout
ctx work link-pr <record-id> https://github.com/ctxrs/ctx/pull/123
ctx work show <record-id>
ctx work context checkout
```

Under the hood, ctx keeps a local SQLite database. The database tracks records, command evidence, pull request links, tags, workspace paths, and reportable context.

## Works with existing agents

Use ctx with the tools already in your loop: Codex, Claude Code, Cursor, shell scripts, test runners, GitHub CLI, and local editors. ctx does not require one model, one provider, or one app.

The contract is simple: a Work Record is the durable layer around the work. Agents can change. The record remains inspectable.

## Old ADE

The earlier ctx Agentic Development Environment has moved to `ctxrs/ade`. This repository now focuses on the local Work Recorder.

## Product shape

ctx is intentionally:

- **Local-first:** SQLite on your machine before anything else.
- **CLI-first:** useful from the terminal, scriptable, and friendly to existing workflows.
- **Agent-neutral:** records work from the tools you choose rather than owning the agent loop.
- **Evidence-oriented:** optimized for review, handoff, audit, and resumption.
- **Small enough to trust:** the recorder should be understandable, portable, and hackable.

## Docs

- [Getting started](docs/getting-started.md)
- [Work model](docs/work-model.md)
- [CLI reference](docs/cli-reference.md)
- [Privacy and storage](docs/privacy-storage.md)

## Build from source

Prerequisites:

- Rust stable
- A normal local C/C++ build toolchain for your platform

Build and test the workspace:

```bash
cargo build --workspace
cargo test --workspace --all-targets
```

Run the repository check script:

```bash
./scripts/check.sh
```

If Bazel is installed, you can run the Bazel test wrapper directly or through Bazel:

```bash
./scripts/bazel-test.sh
bazel test //...
```

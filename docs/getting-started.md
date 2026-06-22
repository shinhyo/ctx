# Getting Started

ctx creates local Work Records for coding-agent tasks. A record keeps the prompt or note, command evidence, pull request links, tags, workspace context, and reportable history for one unit of work.

## Install

```bash
curl -fsSL https://ctx.rs/install | sh
```

Verify the CLI:

```bash
ctx --version
ctx workspace status
ctx work schema
```

## Set up the local workspace

Create the local SQLite store:

```bash
ctx workspace setup
ctx workspace status
```

## Create a work record

Start in the repository where the work is happening.

```bash
cd ~/code/my-project
ctx work record \
  --title "fix checkout retry handling" \
  --body "Investigate flaky checkout retries and make the behavior deterministic." \
  --tag checkout \
  --tag retry \
  --kind task \
  --json
```

The JSON output includes the record id. Use that id when attaching evidence or a pull request.

Run your normal agent or tools from the same workspace. ctx is designed to work beside existing CLIs instead of replacing them.

You can also pipe a longer note into a record:

```bash
cat notes.md | ctx work record --title "checkout retry notes" --body - --kind note
```

## Capture command evidence

Run commands through ctx when their output should become evidence:

```bash
ctx work evidence run --record <record-id> cargo test -p checkout
```

The command is executed normally. ctx stores the command string, exit code, stdout, stderr, start time, and duration.

## Link review state

```bash
ctx work link-pr <record-id> https://github.com/example/project/pull/42
```

## Review and search

```bash
ctx work list
ctx work show <record-id>
ctx work search checkout
ctx work context checkout
ctx work report
```

## Export, import, and validate

```bash
ctx work export --output work-records.json
ctx work import --input work-records.json
ctx work validate
```

## Remove local product data

```bash
ctx workspace uninstall --yes
```

Only run uninstall when you intend to remove the local Work Recorder data store.

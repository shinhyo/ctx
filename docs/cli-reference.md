# CLI Reference

The Work Recorder is CLI-first. These examples match the implemented command surface.

The current CLI is nested under `ctx workspace` and `ctx work`; root-level
commands such as `ctx setup`, `ctx dashboard`, `ctx publish`, `ctx search`, and
`ctx report` are planned product direction, not implemented commands in this
branch.

## Workspace

```bash
ctx workspace setup
ctx workspace status
ctx workspace uninstall --yes
```

- `setup` creates the local Work Recorder data store.
- `status` prints the data root, work record directory, database path, and initialization state.
- `uninstall --yes` removes local Work Recorder product data.

## Schema

```bash
ctx work schema
```

Prints the local SQLite schema.

## Records

```bash
ctx work record --title "task title" --body "prompt, note, or summary" --tag cli --kind task
ctx work record --title "long note" --body - --kind note
ctx work list
ctx work list --limit 50 --json
ctx work show <record-id>
ctx work show <record-id> --json
ctx work search checkout
ctx work search checkout --limit 10 --json
```

- `record` creates a Work Record.
- `--title` is required.
- `--body` accepts inline text. Use `--body -` to read from stdin.
- `--tag` may be repeated.
- `--kind` defaults to `note`.
- `--workspace` can set an explicit workspace path.
- `list`, `show`, and `search` read records back from the local store.

## Context and reports

```bash
ctx work context
ctx work context checkout
ctx work context checkout --limit 20 --json
ctx work report
ctx work report --format json
```

- `context` renders records and evidence for a query as Markdown by default.
- `report` summarizes recent records and evidence as text or JSON.

## Evidence

```bash
ctx work evidence run cargo test
ctx work evidence run --record <record-id> cargo test -p checkout
```

`evidence run` executes the command and stores its command string, exit code, stdout, stderr, start time, and duration. Use `--record <record-id>` to attach the evidence to a specific record.

## Pull requests

```bash
ctx work link-pr <record-id> https://github.com/example/project/pull/42
ctx work link-pr <record-id> https://github.com/example/project/pull/42 --json
```

Attaches a pull request URL to a Work Record in the local store. This does not
publish, create, or update a pull request comment.

## Export, import, and validate

```bash
ctx work export
ctx work export --output work-records.json
ctx work import --input work-records.json
cat work-records.json | ctx work import
ctx work validate
```

- `export` writes a JSON archive to stdout or `--output`.
- `import` reads a JSON archive from `--input` or stdin.
- `import` handles ctx JSON archives only; it does not import local agent
  provider history.
- `validate` checks local Work Recorder storage and prints `valid` when no findings are found.

## Not yet implemented

This branch does not include a dashboard, hosted sync, passive provider hooks,
Git/jj/gh shims, public installer flow, or pull request comment publisher.

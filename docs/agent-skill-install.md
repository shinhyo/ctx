# Agent Skill Install

The ctx agent skill is named `ctx-agent-history-search`.

The name follows the public product language: ctx is local agent history search,
not a model memory or graph database. Use the skill when an agent should query
past local coding-agent sessions before starting work.

## Codex

This repository includes a Codex marketplace catalog at
`.agents/plugins/marketplace.json` and a plugin at
`plugins/ctx-agent-history-search`.

For an unreleased branch or tag, add the marketplace with an explicit ref:

```bash
codex plugin marketplace add ctxrs/ctx --ref ctx/search-sdlc-maturity
```

After the branch is released on the default branch, the ref can be omitted:

```bash
codex plugin marketplace add ctxrs/ctx
```

Then open `/plugins` and install `ctx-agent-history-search`.

## Claude Code

This repository includes a Claude Code marketplace catalog at
`.claude-plugin/marketplace.json`.

For local testing from a checkout:

```text
/plugin marketplace add <path-to-ctx-checkout>
/plugin install ctx-agent-history-search@ctx
```

For GitHub distribution after release:

```text
/plugin marketplace add ctxrs/ctx
/plugin install ctx-agent-history-search@ctx
```

## Cursor

This repository includes a Cursor plugin manifest at
`plugins/ctx-agent-history-search/.cursor-plugin/plugin.json` and a root
`.cursor-plugin/marketplace.json` catalog for submission.

After marketplace acceptance, install it from Cursor Marketplace or with
`/add-plugin` using the name `ctx-agent-history-search`.

## Direct Skill Folder

For agents that support raw Agent Skills, install or copy:

```text
skills/ctx-agent-history-search
```

The plugin copy under `plugins/ctx-agent-history-search/skills/` is intentionally
self-contained so marketplace installs do not depend on files outside the
plugin directory.

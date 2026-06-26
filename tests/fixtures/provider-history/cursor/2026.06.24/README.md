# Cursor native history fixture

Source note: Cursor CLI `2026.06.24-00-45-58-9f61de7` persisted local agent
transcripts under:

```text
~/.cursor/projects/<project-slug>/agent-transcripts/<session-id>/<session-id>.jsonl
```

The adjacent fixture files mirror that disk layout with synthetic project,
session, prompt, assistant, and tool content. They contain no auth files, no
tokens, no private prompts, no copied workspace code, and no
`~/.cursor/ai-tracking` code-tracking database content.

Cursor chat `store.db` files under `$XDG_CONFIG_HOME/cursor/chats` were observed
as persisted local state, but this public fixture and importer cover the primary
event-fidelity path: sanitized agent transcript JSONL.

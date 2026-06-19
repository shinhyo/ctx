# Security Reviews

Record plugin, import/export, path, redaction, and capability security reviews.

## Pending

- Initial plugin threat model review.
- Import/export/redaction review.
- Final security review before full local validation.

## Work CLI Review-Hardening Slice

- Finding: transcript-like event payloads could retain raw text in redaction
  previews when the record shape used event fields instead of message fields.
  Resolution: event-aware omission now treats transcript-like `event_type`
  values and nested payload keys such as `content`, `delta`, `message`, `text`,
  `thought`, and `transcript` as content-bearing fields to omit.
- Finding: plugin manifest validation accepted shallow manifests with unknown
  fields before the daemon/plugin runtime saw them. Resolution: the CLI now
  rejects unknown public v1 manifest fields and delegates structural validation
  to the Rust `PluginManifest` model.
- Finding: shifted-left CLI smoke coverage did not exercise `work-bundle`
  schema output or negative path traversal fixtures. Resolution: the Bazel bin
  smoke test now covers `work-bundle` and rejects `../` bundle object paths.
- Residual risk: local plugin manifests still represent trusted local code once
  installed. The final plugin threat model must explicitly review root escape,
  env leakage, command timeout/output caps, provider ID collisions, and
  diagnostics visibility.

## Store-Backed Work CLI Slice

- Local import/export is scoped to public Work records only: change sets and
  contributions. It does not import hosted, team, enterprise, policy, gate, or
  enforcement state.
- `ctx work import` rejects records whose embedded workspace id does not match
  the selected local workspace before writing.
- `ctx work export` defaults to `safe-summary` redaction and requires explicit
  `--redaction-profile full-local` for raw local records.
- JSON stdout modes suppress diagnostics on stdout so downstream tools do not
  accidentally parse mixed data and diagnostic text.
- Residual risk: import writes are sequential through existing store APIs, not
  yet a single explicit transaction. Existing store validation protects
  workspace relationships and endpoint references, but transactional all-or-none
  import should be added when the store API gains a dedicated import bundle
  method.

## Plugin Contribution Collision Slice

- Duplicate provider/runtime contribution IDs are treated as hard load errors
  because those IDs determine provider authority and adapter ownership.
- Duplicate command/UI contribution IDs are warning diagnostics rather than hard
  errors because current command execution requires both `plugin_id` and
  `command_id`, and registry entries carry plugin identity. Public surfaces must
  still show source labels when displaying these collisions.
- Collision diagnostics are attached to plugin inventory items, so invalid
  provider ownership does not progress into provider adapter sync.
- Residual risk: conflicts with pre-existing non-plugin provider adapters are
  still handled during provider sync by warning and skip behavior; a later
  diagnostics slice should make that visible through the same diagnostic
  surface as plugin inventory collisions.

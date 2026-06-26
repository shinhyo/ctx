# Provider Adapter API

Provider adapters convert local provider transcript files into normalized
sessions and events for indexing.

Adapters should provide:

- provider ID and source format;
- stable source identity and cursor information;
- session IDs and event IDs;
- event type, timestamp, role, text, and metadata when known;
- bounded previews for large tool or command output;
- source path plus cursor or line information for citations;
- clear errors for malformed or unsupported input.

Adapters must be read-only with respect to provider-owned files. They should
prefer structured provider formats over ad hoc text scraping and must document
which fields become searchable.

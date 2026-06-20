-- Reserved local archive-sync cleanup slot.
--
-- Older public local builds briefly created hosted/team archive ingest cursor
-- tables here. The public repo now keeps archive data local and exposes
-- explicit local Work export/import instead of a sync acknowledgement protocol.

DROP INDEX IF EXISTS idx_run_archive_ingest_cursors_org_updated;
DROP INDEX IF EXISTS idx_run_audit_event_ingest_sequences_run_seq;

DROP TABLE IF EXISTS run_archive_ingest_cursors;
DROP TABLE IF EXISTS run_archive_ingest_sequence;
DROP TABLE IF EXISTS run_audit_event_ingest_sequences;

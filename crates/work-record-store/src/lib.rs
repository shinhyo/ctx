use std::{
    fs,
    path::{Path, PathBuf},
};

use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, OptionalExtension, Transaction};
use thiserror::Error;
use uuid::Uuid;
use work_record_core::{Evidence, WorkContext, WorkRecord, WorkRecordArchive};

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("sqlite error: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("time parse error: {0}")]
    Time(#[from] chrono::ParseError),
    #[error("uuid parse error: {0}")]
    Uuid(#[from] uuid::Error),
    #[error("record not found: {0}")]
    NotFound(Uuid),
    #[error("unsupported work record archive version: {0}")]
    UnsupportedArchiveVersion(u32),
    #[error("archive conflicts with existing {kind}: {id}")]
    ImportConflict { kind: &'static str, id: Uuid },
}

pub type Result<T> = std::result::Result<T, StoreError>;

pub struct Store {
    path: PathBuf,
    conn: Connection,
}

impl Store {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let conn = Connection::open(&path)?;
        let store = Self { path, conn };
        store.migrate()?;
        Ok(store)
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn migrate(&self) -> Result<()> {
        self.conn.execute_batch(
            r#"
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS work_records (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                tags_json TEXT NOT NULL,
                kind TEXT NOT NULL,
                workspace TEXT,
                pr_url TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS evidence (
                id TEXT PRIMARY KEY,
                record_id TEXT REFERENCES work_records(id) ON DELETE SET NULL,
                command TEXT NOT NULL,
                exit_code INTEGER NOT NULL,
                stdout TEXT NOT NULL,
                stderr TEXT NOT NULL,
                started_at TEXT NOT NULL,
                duration_ms INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_work_records_created_at
                ON work_records(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_evidence_record_id
                ON evidence(record_id);
            "#,
        )?;
        Ok(())
    }

    pub fn schema(&self) -> Result<String> {
        let mut stmt = self.conn.prepare(
            "SELECT sql FROM sqlite_master
             WHERE type IN ('table', 'index') AND sql IS NOT NULL
             ORDER BY type, name",
        )?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut schema = Vec::new();
        for row in rows {
            schema.push(row?);
        }
        Ok(schema.join(";\n"))
    }

    pub fn insert_record(&self, record: &WorkRecord) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO work_records
            (id, title, body, tags_json, kind, workspace, pr_url, created_at, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            "#,
            params![
                record.id.to_string(),
                record.title,
                record.body,
                serde_json::to_string(&record.tags)?,
                record.kind,
                record.workspace,
                record.pr_url,
                record.created_at.to_rfc3339(),
                record.updated_at.to_rfc3339(),
            ],
        )?;
        Ok(())
    }

    pub fn upsert_record(&self, record: &WorkRecord) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO work_records
            (id, title, body, tags_json, kind, workspace, pr_url, created_at, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                body = excluded.body,
                tags_json = excluded.tags_json,
                kind = excluded.kind,
                workspace = excluded.workspace,
                pr_url = excluded.pr_url,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at
            "#,
            params![
                record.id.to_string(),
                record.title,
                record.body,
                serde_json::to_string(&record.tags)?,
                record.kind,
                record.workspace,
                record.pr_url,
                record.created_at.to_rfc3339(),
                record.updated_at.to_rfc3339(),
            ],
        )?;
        Ok(())
    }

    pub fn get_record(&self, id: Uuid) -> Result<WorkRecord> {
        self.conn
            .query_row(
                record_select_sql("WHERE id = ?1").as_str(),
                params![id.to_string()],
                record_from_row,
            )
            .optional()?
            .ok_or(StoreError::NotFound(id))
    }

    pub fn list_records(&self, limit: usize) -> Result<Vec<WorkRecord>> {
        let mut stmt = self
            .conn
            .prepare(record_select_sql("ORDER BY created_at DESC LIMIT ?1").as_str())?;
        let rows = stmt.query_map(params![limit as i64], record_from_row)?;
        collect_rows(rows)
    }

    pub fn search_records(&self, query: &str, limit: usize) -> Result<Vec<WorkRecord>> {
        let like = format!("%{}%", query);
        let mut stmt = self.conn.prepare(
            record_select_sql(
                "WHERE title LIKE ?1 OR body LIKE ?1 OR tags_json LIKE ?1 ORDER BY created_at DESC LIMIT ?2",
            )
            .as_str(),
        )?;
        let rows = stmt.query_map(params![like, limit as i64], record_from_row)?;
        collect_rows(rows)
    }

    pub fn link_pr(&self, id: Uuid, pr_url: &str) -> Result<WorkRecord> {
        let updated_at = Utc::now().to_rfc3339();
        let changed = self.conn.execute(
            "UPDATE work_records SET pr_url = ?1, updated_at = ?2 WHERE id = ?3",
            params![pr_url, updated_at, id.to_string()],
        )?;
        if changed == 0 {
            return Err(StoreError::NotFound(id));
        }
        self.get_record(id)
    }

    pub fn insert_evidence(&self, evidence: &Evidence) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO evidence
            (id, record_id, command, exit_code, stdout, stderr, started_at, duration_ms)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            "#,
            params![
                evidence.id.to_string(),
                evidence.record_id.map(|id| id.to_string()),
                evidence.command,
                evidence.exit_code,
                evidence.stdout,
                evidence.stderr,
                evidence.started_at.to_rfc3339(),
                evidence.duration_ms,
            ],
        )?;
        Ok(())
    }

    pub fn upsert_evidence(&self, evidence: &Evidence) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO evidence
            (id, record_id, command, exit_code, stdout, stderr, started_at, duration_ms)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            ON CONFLICT(id) DO UPDATE SET
                record_id = excluded.record_id,
                command = excluded.command,
                exit_code = excluded.exit_code,
                stdout = excluded.stdout,
                stderr = excluded.stderr,
                started_at = excluded.started_at,
                duration_ms = excluded.duration_ms
            "#,
            params![
                evidence.id.to_string(),
                evidence.record_id.map(|id| id.to_string()),
                evidence.command,
                evidence.exit_code,
                evidence.stdout,
                evidence.stderr,
                evidence.started_at.to_rfc3339(),
                evidence.duration_ms,
            ],
        )?;
        Ok(())
    }

    pub fn evidence_for_record(&self, record_id: Uuid) -> Result<Vec<Evidence>> {
        let mut stmt = self.conn.prepare(
            evidence_select_sql("WHERE record_id = ?1 ORDER BY started_at DESC").as_str(),
        )?;
        let rows = stmt.query_map(params![record_id.to_string()], evidence_from_row)?;
        collect_rows(rows)
    }

    pub fn recent_evidence(&self, limit: usize) -> Result<Vec<Evidence>> {
        let mut stmt = self
            .conn
            .prepare(evidence_select_sql("ORDER BY started_at DESC LIMIT ?1").as_str())?;
        let rows = stmt.query_map(params![limit as i64], evidence_from_row)?;
        collect_rows(rows)
    }

    pub fn context(&self, query: Option<&str>, limit: usize) -> Result<WorkContext> {
        let records = match query {
            Some(query) => self.search_records(query, limit)?,
            None => self.list_records(limit)?,
        };
        let mut evidence = Vec::new();
        for record in &records {
            evidence.extend(self.evidence_for_record(record.id)?);
        }
        if evidence.is_empty() {
            evidence = self.recent_evidence(limit)?;
        }
        Ok(WorkContext {
            query: query.map(str::to_string),
            records,
            evidence,
        })
    }

    pub fn export_archive(&self) -> Result<WorkRecordArchive> {
        Ok(WorkRecordArchive {
            version: 1,
            records: self.list_records(usize::MAX)?,
            evidence: self.recent_evidence(usize::MAX)?,
        })
    }

    pub fn import_archive(&mut self, archive: &WorkRecordArchive, overwrite: bool) -> Result<()> {
        validate_archive_version(archive)?;
        let tx = self.conn.transaction()?;
        if !overwrite {
            reject_import_conflicts(&tx, archive)?;
        }
        for record in &archive.records {
            upsert_record_tx(&tx, record)?;
        }
        for evidence in &archive.evidence {
            upsert_evidence_tx(&tx, evidence)?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn validate(&self) -> Result<Vec<String>> {
        let integrity: String = self
            .conn
            .query_row("PRAGMA integrity_check", [], |row| row.get(0))?;
        let orphan_count: i64 = self.conn.query_row(
            r#"
            SELECT COUNT(*)
            FROM evidence e
            LEFT JOIN work_records r ON e.record_id = r.id
            WHERE e.record_id IS NOT NULL AND r.id IS NULL
            "#,
            [],
            |row| row.get(0),
        )?;

        let mut findings = Vec::new();
        if integrity != "ok" {
            findings.push(format!("sqlite integrity_check returned {integrity}"));
        }
        if orphan_count > 0 {
            findings.push(format!(
                "{orphan_count} evidence rows reference missing records"
            ));
        }
        Ok(findings)
    }
}

pub fn validate_archive_version(archive: &WorkRecordArchive) -> Result<()> {
    if archive.version == 1 {
        Ok(())
    } else {
        Err(StoreError::UnsupportedArchiveVersion(archive.version))
    }
}

fn reject_import_conflicts(tx: &Transaction<'_>, archive: &WorkRecordArchive) -> Result<()> {
    for record in &archive.records {
        if row_exists(tx, "work_records", record.id)? {
            return Err(StoreError::ImportConflict {
                kind: "record",
                id: record.id,
            });
        }
    }
    for evidence in &archive.evidence {
        if row_exists(tx, "evidence", evidence.id)? {
            return Err(StoreError::ImportConflict {
                kind: "evidence",
                id: evidence.id,
            });
        }
    }
    Ok(())
}

fn row_exists(tx: &Transaction<'_>, table: &str, id: Uuid) -> Result<bool> {
    let sql = format!("SELECT 1 FROM {table} WHERE id = ?1");
    Ok(tx
        .query_row(&sql, params![id.to_string()], |_| Ok(()))
        .optional()?
        .is_some())
}

fn upsert_record_tx(tx: &Transaction<'_>, record: &WorkRecord) -> Result<()> {
    tx.execute(
        r#"
        INSERT INTO work_records
        (id, title, body, tags_json, kind, workspace, pr_url, created_at, updated_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            body = excluded.body,
            tags_json = excluded.tags_json,
            kind = excluded.kind,
            workspace = excluded.workspace,
            pr_url = excluded.pr_url,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at
        "#,
        params![
            record.id.to_string(),
            record.title,
            record.body,
            serde_json::to_string(&record.tags)?,
            record.kind,
            record.workspace,
            record.pr_url,
            record.created_at.to_rfc3339(),
            record.updated_at.to_rfc3339(),
        ],
    )?;
    Ok(())
}

fn upsert_evidence_tx(tx: &Transaction<'_>, evidence: &Evidence) -> Result<()> {
    tx.execute(
        r#"
        INSERT INTO evidence
        (id, record_id, command, exit_code, stdout, stderr, started_at, duration_ms)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
        ON CONFLICT(id) DO UPDATE SET
            record_id = excluded.record_id,
            command = excluded.command,
            exit_code = excluded.exit_code,
            stdout = excluded.stdout,
            stderr = excluded.stderr,
            started_at = excluded.started_at,
            duration_ms = excluded.duration_ms
        "#,
        params![
            evidence.id.to_string(),
            evidence.record_id.map(|id| id.to_string()),
            evidence.command,
            evidence.exit_code,
            evidence.stdout,
            evidence.stderr,
            evidence.started_at.to_rfc3339(),
            evidence.duration_ms,
        ],
    )?;
    Ok(())
}

fn record_select_sql(tail: &str) -> String {
    format!(
        "SELECT id, title, body, tags_json, kind, workspace, pr_url, created_at, updated_at FROM work_records {tail}"
    )
}

fn evidence_select_sql(tail: &str) -> String {
    format!(
        "SELECT id, record_id, command, exit_code, stdout, stderr, started_at, duration_ms FROM evidence {tail}"
    )
}

fn record_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<WorkRecord> {
    let tags_json: String = row.get(3)?;
    Ok(WorkRecord {
        id: parse_uuid(row.get::<_, String>(0)?)?,
        title: row.get(1)?,
        body: row.get(2)?,
        tags: serde_json::from_str(&tags_json)
            .map_err(|err| rusqlite::Error::ToSqlConversionFailure(Box::new(err)))?,
        kind: row.get(4)?,
        workspace: row.get(5)?,
        pr_url: row.get(6)?,
        created_at: parse_time(row.get::<_, String>(7)?)?,
        updated_at: parse_time(row.get::<_, String>(8)?)?,
    })
}

fn evidence_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<Evidence> {
    let record_id: Option<String> = row.get(1)?;
    Ok(Evidence {
        id: parse_uuid(row.get::<_, String>(0)?)?,
        record_id: record_id
            .map(parse_uuid)
            .transpose()
            .map_err(|err| rusqlite::Error::ToSqlConversionFailure(Box::new(err)))?,
        command: row.get(2)?,
        exit_code: row.get(3)?,
        stdout: row.get(4)?,
        stderr: row.get(5)?,
        started_at: parse_time(row.get::<_, String>(6)?)?,
        duration_ms: row.get(7)?,
    })
}

fn parse_uuid(value: String) -> rusqlite::Result<Uuid> {
    Uuid::parse_str(&value).map_err(|err| rusqlite::Error::ToSqlConversionFailure(Box::new(err)))
}

fn parse_time(value: String) -> rusqlite::Result<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(&value)
        .map(|value| value.with_timezone(&Utc))
        .map_err(|err| rusqlite::Error::ToSqlConversionFailure(Box::new(err)))
}

fn collect_rows<T>(
    rows: rusqlite::MappedRows<'_, impl FnMut(&rusqlite::Row<'_>) -> rusqlite::Result<T>>,
) -> Result<Vec<T>> {
    let mut values = Vec::new();
    for row in rows {
        values.push(row?);
    }
    Ok(values)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tempdir() -> tempfile::TempDir {
        let root = std::env::current_dir().unwrap().join("target/test-data");
        fs::create_dir_all(&root).unwrap();
        tempfile::Builder::new()
            .prefix("work-record-store-")
            .tempdir_in(root)
            .unwrap()
    }

    #[test]
    fn stores_searches_and_exports_records() {
        let temp = tempdir();
        let store = Store::open(temp.path().join("work.sqlite")).unwrap();
        let record = WorkRecord::new(
            "Ship importer",
            "import and export json archives",
            vec!["import".into(), "json".into()],
            "task",
            Some("ctx".into()),
        );
        store.insert_record(&record).unwrap();

        let evidence = Evidence::new(
            Some(record.id),
            "cargo test",
            0,
            "ok".into(),
            String::new(),
            Utc::now(),
            12,
        );
        store.insert_evidence(&evidence).unwrap();

        assert_eq!(store.search_records("json", 10).unwrap()[0].id, record.id);
        assert_eq!(
            store.context(Some("import"), 10).unwrap().evidence[0].id,
            evidence.id
        );

        let archive = store.export_archive().unwrap();
        let mut second = Store::open(temp.path().join("second.sqlite")).unwrap();
        second.import_archive(&archive, false).unwrap();
        assert_eq!(second.get_record(record.id).unwrap().title, "Ship importer");
        assert!(second.validate().unwrap().is_empty());
    }

    #[test]
    fn rejects_unsupported_archive_versions() {
        let temp = tempdir();
        let mut store = Store::open(temp.path().join("work.sqlite")).unwrap();
        let archive = WorkRecordArchive {
            version: 2,
            records: Vec::new(),
            evidence: Vec::new(),
        };

        assert!(matches!(
            store.import_archive(&archive, false),
            Err(StoreError::UnsupportedArchiveVersion(2))
        ));
    }

    #[test]
    fn import_rejects_conflicts_unless_overwrite_is_explicit() {
        let temp = tempdir();
        let mut store = Store::open(temp.path().join("work.sqlite")).unwrap();
        let mut record = WorkRecord::new("Original", "body", Vec::new(), "note", None);
        store.insert_record(&record).unwrap();

        record.title = "Replacement".into();
        let archive = WorkRecordArchive {
            version: 1,
            records: vec![record.clone()],
            evidence: Vec::new(),
        };

        assert!(matches!(
            store.import_archive(&archive, false),
            Err(StoreError::ImportConflict { kind: "record", .. })
        ));
        assert_eq!(store.get_record(record.id).unwrap().title, "Original");

        store.import_archive(&archive, true).unwrap();
        assert_eq!(store.get_record(record.id).unwrap().title, "Replacement");
    }

    #[test]
    fn failed_import_rolls_back_all_rows() {
        let temp = tempdir();
        let mut store = Store::open(temp.path().join("work.sqlite")).unwrap();
        let record = WorkRecord::new("Atomic", "body", Vec::new(), "note", None);
        let evidence = Evidence::new(
            Some(Uuid::new_v4()),
            "cargo test",
            0,
            String::new(),
            String::new(),
            Utc::now(),
            1,
        );
        let archive = WorkRecordArchive {
            version: 1,
            records: vec![record.clone()],
            evidence: vec![evidence],
        };

        assert!(store.import_archive(&archive, false).is_err());
        assert!(matches!(
            store.get_record(record.id),
            Err(StoreError::NotFound(_))
        ));
    }
}

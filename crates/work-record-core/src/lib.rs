use std::{env, path::PathBuf};

use chrono::{DateTime, Utc};
use directories::BaseDirs;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("could not determine a home directory for the default ctx data root")]
    MissingHome,
}

pub type Result<T> = std::result::Result<T, CoreError>;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkRecord {
    pub id: Uuid,
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
    pub kind: String,
    pub workspace: Option<String>,
    pub pr_url: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl WorkRecord {
    pub fn new(
        title: impl Into<String>,
        body: impl Into<String>,
        tags: Vec<String>,
        kind: impl Into<String>,
        workspace: Option<String>,
    ) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            title: title.into(),
            body: body.into(),
            tags,
            kind: kind.into(),
            workspace,
            pr_url: None,
            created_at: now,
            updated_at: now,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Evidence {
    pub id: Uuid,
    pub record_id: Option<Uuid>,
    pub command: String,
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
    pub started_at: DateTime<Utc>,
    pub duration_ms: i64,
}

impl Evidence {
    pub fn new(
        record_id: Option<Uuid>,
        command: impl Into<String>,
        exit_code: i32,
        stdout: String,
        stderr: String,
        started_at: DateTime<Utc>,
        duration_ms: i64,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            record_id,
            command: command.into(),
            exit_code,
            stdout,
            stderr,
            started_at,
            duration_ms,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkRecordArchive {
    pub version: u32,
    pub records: Vec<WorkRecord>,
    pub evidence: Vec<Evidence>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkContext {
    pub query: Option<String>,
    pub records: Vec<WorkRecord>,
    pub evidence: Vec<Evidence>,
}

pub fn default_data_root() -> Result<PathBuf> {
    if let Some(value) = env::var_os("CTX_DATA_ROOT") {
        return Ok(PathBuf::from(value));
    }

    let base = BaseDirs::new().ok_or(CoreError::MissingHome)?;
    Ok(base.home_dir().join(".ctx"))
}

pub fn work_record_dir(root: PathBuf) -> PathBuf {
    root.join("work-record")
}

pub fn database_path(root: PathBuf) -> PathBuf {
    work_record_dir(root).join("work-record.sqlite")
}

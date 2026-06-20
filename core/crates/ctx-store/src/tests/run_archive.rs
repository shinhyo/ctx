use super::{setup_session_fixture, sqlite_url, Store};
use chrono::Utc;
use ctx_core::ids::{MessageId, RunId, SessionId, TaskId, TurnId, WorkspaceId, WorktreeId};
use ctx_core::models::{
    ArchiveVisibility, AuditActor, AuditActorKind, AuditEvent, AuditEventKind, RunArchiveState,
    RunRecord, RunStatus,
};
use sqlx::{Row, SqlitePool};

#[tokio::test]
async fn runs_archive_audit_migration_backfills_existing_run_ids() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("db.sqlite");
    std::fs::File::create(&db_path).unwrap();
    let pool = SqlitePool::connect(&sqlite_url(&db_path)).await.unwrap();

    sqlx::query(r#"CREATE TABLE workspaces (id TEXT PRIMARY KEY NOT NULL)"#)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query(r#"CREATE TABLE tasks (id TEXT PRIMARY KEY NOT NULL)"#)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query(r#"CREATE TABLE worktrees (id TEXT PRIMARY KEY NOT NULL)"#)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query(
        r#"CREATE TABLE sessions (
            id TEXT PRIMARY KEY NOT NULL,
            task_id TEXT NOT NULL,
            workspace_id TEXT NOT NULL,
            worktree_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )"#,
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        r#"CREATE TABLE session_turns (
            turn_id TEXT PRIMARY KEY NOT NULL,
            session_id TEXT NOT NULL,
            run_id TEXT,
            status TEXT NOT NULL,
            started_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )"#,
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        r#"CREATE TABLE session_events (
            seq INTEGER PRIMARY KEY,
            session_id TEXT NOT NULL,
            run_id TEXT,
            event_type TEXT NOT NULL,
            created_at TEXT NOT NULL
        )"#,
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        r#"CREATE TABLE messages (
            id TEXT PRIMARY KEY NOT NULL,
            session_id TEXT NOT NULL,
            run_id TEXT,
            created_at TEXT NOT NULL
        )"#,
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        r#"CREATE TABLE subagent_invocation_children (
            child_session_id TEXT NOT NULL,
            run_id TEXT
        )"#,
    )
    .execute(&pool)
    .await
    .unwrap();

    let workspace_id = WorkspaceId::new().0.to_string();
    let task_id = TaskId::new().0.to_string();
    let worktree_id = WorktreeId::new().0.to_string();
    let session_id = SessionId::new().0.to_string();
    let turn_id = TurnId::new().0.to_string();
    let run_id = RunId::new().0.to_string();

    sqlx::query("INSERT INTO workspaces (id) VALUES (?)")
        .bind(&workspace_id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO tasks (id) VALUES (?)")
        .bind(&task_id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO worktrees (id) VALUES (?)")
        .bind(&worktree_id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO sessions (id, task_id, workspace_id, worktree_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(&session_id)
    .bind(&task_id)
    .bind(&workspace_id)
    .bind(&worktree_id)
    .bind("2026-04-24T09:00:00Z")
    .bind("2026-04-24T09:06:00Z")
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO session_turns (turn_id, session_id, run_id, status, started_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(&turn_id)
    .bind(&session_id)
    .bind(&run_id)
    .bind("completed")
    .bind("2026-04-24T09:01:00Z")
    .bind("2026-04-24T09:05:00Z")
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO session_events (seq, session_id, run_id, event_type, created_at) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(1_i64)
    .bind(&session_id)
    .bind(&run_id)
    .bind("done")
    .bind("2026-04-24T09:05:00Z")
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO messages (id, session_id, run_id, created_at) VALUES (?, ?, ?, ?)")
        .bind(MessageId::new().0.to_string())
        .bind(&session_id)
        .bind(&run_id)
        .bind("2026-04-24T09:04:00Z")
        .execute(&pool)
        .await
        .unwrap();

    for migration_sql in [
        include_str!("../../migrations/0069_reserved_local_schema_slot.sql"),
        include_str!("../../migrations/0070_runs_archive_audit.sql"),
    ] {
        for statement in migration_sql
            .split(";\n\n")
            .map(str::trim)
            .filter(|statement| !statement.is_empty())
        {
            sqlx::query(statement).execute(&pool).await.unwrap();
        }
    }

    let row = sqlx::query(
        r#"SELECT session_id, task_id, workspace_id, worktree_id, status, archive_state,
                  archive_visibility, started_at, completed_at
           FROM runs
           WHERE id = ?"#,
    )
    .bind(&run_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(row.try_get::<String, _>("session_id").unwrap(), session_id);
    assert_eq!(row.try_get::<String, _>("task_id").unwrap(), task_id);
    assert_eq!(
        row.try_get::<String, _>("workspace_id").unwrap(),
        workspace_id
    );
    assert_eq!(
        row.try_get::<String, _>("worktree_id").unwrap(),
        worktree_id
    );
    assert_eq!(row.try_get::<String, _>("status").unwrap(), "completed");
    assert_eq!(row.try_get::<String, _>("archive_state").unwrap(), "active");
    assert_eq!(
        row.try_get::<String, _>("archive_visibility").unwrap(),
        "local_only"
    );
    assert_eq!(
        row.try_get::<Option<String>, _>("started_at")
            .unwrap()
            .as_deref(),
        Some("2026-04-24T09:01:00Z")
    );
    assert_eq!(
        row.try_get::<Option<String>, _>("completed_at")
            .unwrap()
            .as_deref(),
        Some("2026-04-24T09:05:00Z")
    );

    let audit_table_exists: i64 = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'run_audit_events')",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(audit_table_exists, 1);

    pool.close().await;
}

#[tokio::test]
async fn private_sync_migration_slots_repair_legacy_rows_and_drop_tables() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("db.sqlite");

    Store::open(&db_path).await.unwrap().close().await;

    let pool = SqlitePool::connect(&sqlite_url(&db_path)).await.unwrap();
    sqlx::query("UPDATE _sqlx_migrations SET description = ?, checksum = ? WHERE version = ?")
        .bind("org policy and run grants")
        .bind(vec![0_u8])
        .bind(69_i64)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("UPDATE _sqlx_migrations SET description = ?, checksum = ? WHERE version = ?")
        .bind("run archive ingest")
        .bind(vec![0_u8])
        .bind(71_i64)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS run_archive_ingest_sequence (id INTEGER PRIMARY KEY, next_seq INTEGER NOT NULL)",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS run_audit_event_ingest_sequences (audit_event_id TEXT PRIMARY KEY, run_id TEXT, ingest_seq INTEGER NOT NULL, created_at TEXT NOT NULL)",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS run_archive_ingest_cursors (run_id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL, org_id TEXT, archive_visibility TEXT NOT NULL, updated_at TEXT NOT NULL)",
    )
    .execute(&pool)
    .await
    .unwrap();
    pool.close().await;

    let reopened = Store::open(&db_path).await.unwrap();
    let descriptions = sqlx::query(
        "SELECT version, description FROM _sqlx_migrations WHERE version IN (69, 71) ORDER BY version",
    )
    .fetch_all(reopened.pool())
    .await
    .unwrap();
    assert_eq!(descriptions.len(), 2);
    assert_eq!(
        descriptions[0].try_get::<String, _>("description").unwrap(),
        "reserved local schema slot"
    );
    assert_eq!(
        descriptions[1].try_get::<String, _>("description").unwrap(),
        "reserved local archive sync cleanup"
    );
    for table in [
        "run_archive_ingest_sequence",
        "run_audit_event_ingest_sequences",
        "run_archive_ingest_cursors",
    ] {
        let exists: i64 = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?)",
        )
        .bind(table)
        .fetch_one(reopened.pool())
        .await
        .unwrap();
        assert_eq!(
            exists, 0,
            "{table} should be dropped by public local cleanup"
        );
    }
    reopened.close().await;
}

#[tokio::test]
async fn run_record_round_trip_keeps_archive_state_separate_from_visibility() {
    let fixture = setup_session_fixture().await;
    let now = Utc::now();
    let run_id = RunId::new();
    let initial = RunRecord {
        id: run_id,
        session_id: fixture.session_id,
        task_id: fixture.task_id,
        workspace_id: fixture.workspace_id,
        worktree_id: fixture.worktree_id,
        parent_run_id: None,
        account_id: None,
        org_id: None,
        status: RunStatus::Running,
        archive_state: RunArchiveState::Active,
        archive_visibility: ArchiveVisibility::LocalOnly,
        retention_policy: None,
        created_at: now,
        started_at: Some(now),
        completed_at: None,
        archived_at: None,
        updated_at: now,
    };

    fixture.store.upsert_run(initial.clone()).await.unwrap();

    let mut archived = initial.clone();
    archived.status = RunStatus::Completed;
    archived.archive_state = RunArchiveState::Archived;
    archived.completed_at = Some(now);
    archived.archived_at = Some(now);
    archived.updated_at = now;
    fixture.store.upsert_run(archived.clone()).await.unwrap();

    let stored = fixture.store.get_run(run_id).await.unwrap().unwrap();
    assert_eq!(stored.archive_state, RunArchiveState::Archived);
    assert_eq!(stored.archive_visibility, ArchiveVisibility::LocalOnly);
    assert!(stored.retention_policy.is_none());

    let audit = AuditEvent {
        id: uuid::Uuid::new_v4().to_string(),
        workspace_id: fixture.workspace_id,
        task_id: Some(fixture.task_id),
        session_id: Some(fixture.session_id),
        run_id: Some(run_id),
        account_id: None,
        org_id: None,
        actor: AuditActor {
            kind: AuditActorKind::System,
            account_id: None,
            org_id: None,
            membership_role: None,
        },
        event_kind: AuditEventKind::HistoryAccessed,
        archive_visibility: Some(ArchiveVisibility::LocalOnly),
        retention_policy: stored.retention_policy.clone(),
        payload_json: serde_json::json!({ "surface": "desktop", "action": "view" }),
        created_at: now,
    };
    fixture
        .store
        .append_run_audit_event(audit.clone())
        .await
        .unwrap();

    let audit_events = fixture.store.list_run_audit_events(run_id).await.unwrap();
    assert_eq!(audit_events, vec![audit]);
}

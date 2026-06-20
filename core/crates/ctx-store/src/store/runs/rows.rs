use super::*;

pub(super) fn build_run_record_from_row(row: SqliteRow) -> Result<RunRecord> {
    let id: String = row.try_get("id")?;
    let session_id: String = row.try_get("session_id")?;
    let task_id: String = row.try_get("task_id")?;
    let workspace_id: String = row.try_get("workspace_id")?;
    let worktree_id: String = row.try_get("worktree_id")?;
    let parent_run_id: Option<String> = row.try_get("parent_run_id")?;
    let account_id: Option<String> = row.try_get("account_id")?;
    let org_id: Option<String> = row.try_get("org_id")?;
    let status: String = row.try_get("status")?;
    let archive_state: String = row.try_get("archive_state")?;
    let archive_visibility: String = row.try_get("archive_visibility")?;
    let retention_policy_key: Option<String> = row.try_get("retention_policy_key")?;
    let retention_legal_hold_key: Option<String> = row.try_get("retention_legal_hold_key")?;
    let created_at: String = row.try_get("created_at")?;
    let started_at: Option<String> = row.try_get("started_at")?;
    let completed_at: Option<String> = row.try_get("completed_at")?;
    let archived_at: Option<String> = row.try_get("archived_at")?;
    let updated_at: String = row.try_get("updated_at")?;

    Ok(RunRecord {
        id: parse_uuid_id(id, "runs.id", RunId)?,
        session_id: parse_uuid_id(session_id, "runs.session_id", SessionId)?,
        task_id: parse_uuid_id(task_id, "runs.task_id", TaskId)?,
        workspace_id: parse_uuid_id(workspace_id, "runs.workspace_id", WorkspaceId)?,
        worktree_id: parse_uuid_id(worktree_id, "runs.worktree_id", WorktreeId)?,
        parent_run_id: parse_opt_uuid_id(parent_run_id, "runs.parent_run_id", RunId)?,
        account_id: parse_opt_uuid_id(account_id, "runs.account_id", AccountId)?,
        org_id: parse_opt_uuid_id(org_id, "runs.org_id", OrgId)?,
        status: RunStatus::parse(&status)
            .with_context(|| format!("invalid runs.status value: {status}"))?,
        archive_state: RunArchiveState::parse(&archive_state)
            .with_context(|| format!("invalid runs.archive_state value: {archive_state}"))?,
        archive_visibility: ArchiveVisibility::parse(&archive_visibility).with_context(|| {
            format!("invalid runs.archive_visibility value: {archive_visibility}")
        })?,
        retention_policy: retention_policy_key.map(|policy_key| RetentionPolicyRef {
            policy_key,
            legal_hold_key: retention_legal_hold_key,
        }),
        created_at: parse_dt(&created_at)?,
        started_at: started_at.as_deref().map(parse_dt).transpose()?,
        completed_at: completed_at.as_deref().map(parse_dt).transpose()?,
        archived_at: archived_at.as_deref().map(parse_dt).transpose()?,
        updated_at: parse_dt(&updated_at)?,
    })
}

pub(super) fn build_audit_event_from_row(row: SqliteRow) -> Result<AuditEvent> {
    let id: String = row.try_get("id")?;
    let workspace_id: String = row.try_get("workspace_id")?;
    let task_id: Option<String> = row.try_get("task_id")?;
    let session_id: Option<String> = row.try_get("session_id")?;
    let run_id: Option<String> = row.try_get("run_id")?;
    let account_id: Option<String> = row.try_get("account_id")?;
    let org_id: Option<String> = row.try_get("org_id")?;
    let actor_kind: String = row.try_get("actor_kind")?;
    let actor_account_id: Option<String> = row.try_get("actor_account_id")?;
    let actor_org_id: Option<String> = row.try_get("actor_org_id")?;
    let actor_membership_role: Option<String> = row.try_get("actor_membership_role")?;
    let event_kind: String = row.try_get("event_kind")?;
    let archive_visibility: Option<String> = row.try_get("archive_visibility")?;
    let retention_policy_key: Option<String> = row.try_get("retention_policy_key")?;
    let retention_legal_hold_key: Option<String> = row.try_get("retention_legal_hold_key")?;
    let payload_json: String = row.try_get("payload_json")?;
    let created_at: String = row.try_get("created_at")?;

    Ok(AuditEvent {
        id,
        workspace_id: parse_uuid_id(workspace_id, "run_audit_events.workspace_id", WorkspaceId)?,
        task_id: parse_opt_uuid_id(task_id, "run_audit_events.task_id", TaskId)?,
        session_id: parse_opt_uuid_id(session_id, "run_audit_events.session_id", SessionId)?,
        run_id: parse_opt_uuid_id(run_id, "run_audit_events.run_id", RunId)?,
        account_id: parse_opt_uuid_id(account_id, "run_audit_events.account_id", AccountId)?,
        org_id: parse_opt_uuid_id(org_id, "run_audit_events.org_id", OrgId)?,
        actor: AuditActor {
            kind: AuditActorKind::parse(&actor_kind)
                .with_context(|| format!("invalid run_audit_events.actor_kind: {actor_kind}"))?,
            account_id: parse_opt_uuid_id(
                actor_account_id,
                "run_audit_events.actor_account_id",
                AccountId,
            )?,
            org_id: parse_opt_uuid_id(actor_org_id, "run_audit_events.actor_org_id", OrgId)?,
            membership_role: actor_membership_role,
        },
        event_kind: AuditEventKind::parse(&event_kind)
            .with_context(|| format!("invalid run_audit_events.event_kind: {event_kind}"))?,
        archive_visibility: archive_visibility
            .map(|value| {
                ArchiveVisibility::parse(&value).with_context(|| {
                    format!("invalid run_audit_events.archive_visibility: {value}")
                })
            })
            .transpose()?,
        retention_policy: retention_policy_key.map(|policy_key| RetentionPolicyRef {
            policy_key,
            legal_hold_key: retention_legal_hold_key,
        }),
        payload_json: serde_json::from_str(&payload_json)
            .with_context(|| "failed to parse run_audit_events.payload_json".to_string())?,
        created_at: parse_dt(&created_at)?,
    })
}

fn parse_uuid_id<T>(value: String, field_name: &str, wrap: fn(uuid::Uuid) -> T) -> Result<T> {
    Ok(wrap(uuid::Uuid::parse_str(&value).with_context(|| {
        format!("invalid UUID in {field_name}: {value}")
    })?))
}

fn parse_opt_uuid_id<T>(
    value: Option<String>,
    field_name: &str,
    wrap: fn(uuid::Uuid) -> T,
) -> Result<Option<T>> {
    value
        .map(|value| parse_uuid_id(value, field_name, wrap))
        .transpose()
}

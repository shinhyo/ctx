use super::*;

const PROJECTOR_SOURCE_KIND: &str = "ade_session_projector";
const PROJECTOR_EVENT_BASE_SEQUENCE: i64 = 4_000_000_000_000_000_000;
const PROJECTOR_EVENT_SEQUENCE_SPAN: u64 = 1_000_000_000_000_000_000;
const PROJECTOR_TEXT_LIMIT: usize = 8 * 1024;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct WorkProjectionResult {
    pub work_records: usize,
    pub links: usize,
    pub events: usize,
}

impl WorkProjectionResult {
    fn add(&mut self, other: WorkProjectionResult) {
        self.work_records += other.work_records;
        self.links += other.links;
        self.events += other.events;
    }
}

impl Store {
    pub async fn project_task_sessions_to_work(
        &self,
        task_id: TaskId,
    ) -> Result<WorkProjectionResult> {
        let sessions = self.list_all_sessions_for_task(task_id).await?;
        let mut result = WorkProjectionResult::default();
        for session in sessions {
            result.add(self.project_session_to_work(session.id).await?);
        }
        Ok(result)
    }

    pub async fn project_session_to_work(
        &self,
        session_id: SessionId,
    ) -> Result<WorkProjectionResult> {
        let Some(session) = self.get_session(session_id).await? else {
            anyhow::bail!("session does not exist");
        };
        let task = self
            .get_task(session.task_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("session task does not exist"))?;
        let worktree = self.get_worktree(session.worktree_id).await?;

        let now = Utc::now();
        let work_id = if let Some(record) = self
            .find_work_record_by_link(
                session.workspace_id,
                WorkLinkTargetKind::Session,
                &session.id.0.to_string(),
            )
            .await?
        {
            record.work_id
        } else if let Some(record) = self
            .find_work_record_by_link(
                session.workspace_id,
                WorkLinkTargetKind::Task,
                &session.task_id.0.to_string(),
            )
            .await?
        {
            record.work_id
        } else {
            stable_task_work_id(session.task_id)
        };

        let created_at = [task.created_at, session.created_at]
            .into_iter()
            .min()
            .unwrap_or(session.created_at);
        let updated_at = [task.updated_at, session.updated_at]
            .into_iter()
            .max()
            .unwrap_or(now);

        let record = WorkRecord {
            work_id: work_id.clone(),
            workspace_id: session.workspace_id,
            title: Some(bounded_redacted_text(&task.title, 1_000)),
            objective: task
                .description
                .as_deref()
                .map(|description| bounded_redacted_text(description, 2_000)),
            lifecycle: lifecycle_from_task_status(&task.status),
            primary_repo_root: None,
            primary_branch: worktree.as_ref().and_then(|worktree| {
                worktree
                    .git_branch
                    .as_deref()
                    .map(|branch| bounded_redacted_text(branch, 500))
            }),
            base_commit: worktree
                .as_ref()
                .map(|worktree| worktree.base_commit_sha.clone()),
            head_commit: None,
            current_diff_fingerprint: None,
            trust_verdict: WorkTrustVerdict::UntrustedLocalCapture,
            summary_freshness: WorkSummaryFreshness::Missing,
            metadata_json: Some(serde_json::json!({
                "projection": "ade_session",
                "bounded": true,
                "notes": [
                    "projects durable session events only",
                    "transient stream-only events are unavailable for backfill"
                ]
            })),
            created_at,
            updated_at,
            schema_version: WORK_OBSERVABILITY_SCHEMA_VERSION,
        };
        self.upsert_work_record(&record).await?;

        let mut result = WorkProjectionResult {
            work_records: 1,
            links: 0,
            events: 0,
        };

        for link in base_session_links(&session, &work_id, now) {
            self.upsert_work_record_link(&link).await?;
            result.links += 1;
        }

        let events = self.list_session_events(session.id).await?;
        let mut run_ids = HashSet::new();
        for event in &events {
            if let Some(run_id) = event.run_id {
                run_ids.insert(run_id);
            }
        }
        for run_id in run_ids {
            let link = projection_link(
                session.workspace_id,
                &work_id,
                WorkLinkTargetKind::Run,
                &run_id.0.to_string(),
                WorkLinkRole::Source,
                now,
            );
            self.upsert_work_record_link(&link).await?;
            result.links += 1;
        }

        for event in session_state_events(&session, &work_id, now) {
            self.append_work_event(&event).await?;
            result.events += 1;
        }

        for event in events
            .iter()
            .filter_map(|event| projected_session_event(&session, &work_id, event))
        {
            self.append_work_event(&event).await?;
            result.events += 1;
        }

        for artifact in self.list_session_artifacts(session.id).await? {
            let link = WorkRecordLink {
                target_json: Some(serde_json::json!({
                    "name": artifact.name.as_deref().map(|name| bounded_redacted_text(name, 300)),
                    "mime_type": artifact.mime_type,
                    "bytes": artifact.bytes,
                })),
                ..projection_link(
                    session.workspace_id,
                    &work_id,
                    WorkLinkTargetKind::Artifact,
                    &artifact.id.0.to_string(),
                    WorkLinkRole::Result,
                    artifact.created_at,
                )
            };
            self.upsert_work_record_link(&link).await?;
            result.links += 1;

            self.append_work_event(&WorkEvent {
                event_id: stable_work_event_id(&format!("artifact:{}", artifact.id.0)),
                work_id: work_id.clone(),
                workspace_id: session.workspace_id,
                sequence: stable_projector_sequence(&format!("artifact:{}", artifact.id.0)),
                source_kind: Some(PROJECTOR_SOURCE_KIND.to_string()),
                source_id: Some(artifact.id.0.to_string()),
                event_type: WorkEventType::ArtifactCreated,
                event_time: artifact.created_at,
                actor_kind: WorkActorKind::Agent,
                provider: Some(session.provider_id.clone()),
                harness: Some(session.agent_role.clone()),
                model: Some(session.model_id.clone()),
                redaction_class: WorkRedactionClass::LocalRedacted,
                source: RecordSource::Session,
                fidelity: RecordFidelity::Declared,
                trust: RecordTrust::Low,
                payload_json: None,
                redacted_text: Some(bounded_redacted_text(
                    &format!(
                        "Artifact created: {} ({}, {} bytes)",
                        artifact.name.as_deref().unwrap_or("unnamed"),
                        artifact.mime_type,
                        artifact.bytes
                    ),
                    PROJECTOR_TEXT_LIMIT,
                )),
                artifact_ref: None,
                created_at: now,
                schema_version: WORK_OBSERVABILITY_SCHEMA_VERSION,
            })
            .await?;
            result.events += 1;
        }

        for invocation in self
            .list_subagent_invocations_for_session(session.id, None)
            .await?
        {
            self.append_work_event(&WorkEvent {
                event_id: stable_work_event_id(&format!("subagent_invocation:{}", invocation.id)),
                work_id: work_id.clone(),
                workspace_id: session.workspace_id,
                sequence: stable_projector_sequence(&format!(
                    "subagent_invocation:{}",
                    invocation.id
                )),
                source_kind: Some(PROJECTOR_SOURCE_KIND.to_string()),
                source_id: Some(invocation.id.clone()),
                event_type: WorkEventType::Session,
                event_time: invocation.updated_at,
                actor_kind: WorkActorKind::Subagent,
                provider: Some(session.provider_id.clone()),
                harness: Some(session.agent_role.clone()),
                model: Some(session.model_id.clone()),
                redaction_class: WorkRedactionClass::LocalRedacted,
                source: RecordSource::Session,
                fidelity: RecordFidelity::Declared,
                trust: RecordTrust::Low,
                payload_json: None,
                redacted_text: Some(bounded_redacted_text(
                    &format!(
                        "Subagent invocation {} status {} children {}",
                        invocation.id,
                        invocation.status,
                        invocation.children.len()
                    ),
                    PROJECTOR_TEXT_LIMIT,
                )),
                artifact_ref: None,
                created_at: now,
                schema_version: WORK_OBSERVABILITY_SCHEMA_VERSION,
            })
            .await?;
            result.events += 1;

            for child in invocation.children {
                let link = projection_link(
                    session.workspace_id,
                    &work_id,
                    WorkLinkTargetKind::Session,
                    &child.child_session_id.0.to_string(),
                    WorkLinkRole::Child,
                    child.updated_at,
                );
                self.upsert_work_record_link(&link).await?;
                result.links += 1;
                if let Some(run_id) = child.run_id {
                    let link = projection_link(
                        session.workspace_id,
                        &work_id,
                        WorkLinkTargetKind::Run,
                        &run_id.0.to_string(),
                        WorkLinkRole::Child,
                        child.updated_at,
                    );
                    self.upsert_work_record_link(&link).await?;
                    result.links += 1;
                }
            }
        }

        Ok(result)
    }
}

fn stable_task_work_id(task_id: TaskId) -> WorkRecordId {
    WorkRecordId::from_id(format!("wrk_ade_task_{}", task_id.0.simple()))
}

fn stable_work_link_id(
    work_id: &WorkRecordId,
    target_kind: WorkLinkTargetKind,
    target_id: &str,
    role: WorkLinkRole,
) -> WorkRecordLinkId {
    WorkRecordLinkId::from_id(format!(
        "wln_ade_{}_{target_kind:?}_{}_{role:?}",
        work_id.0,
        target_id.replace('-', "")
    ))
}

fn stable_work_event_id(source_id: &str) -> WorkEventId {
    WorkEventId::from_id(format!(
        "wev_ade_{}",
        source_id
            .chars()
            .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '_' })
            .collect::<String>()
    ))
}

fn stable_projector_sequence(source_id: &str) -> i64 {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in source_id.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    PROJECTOR_EVENT_BASE_SEQUENCE + (hash % PROJECTOR_EVENT_SEQUENCE_SPAN) as i64
}

fn projection_link(
    workspace_id: WorkspaceId,
    work_id: &WorkRecordId,
    target_kind: WorkLinkTargetKind,
    target_id: &str,
    role: WorkLinkRole,
    timestamp: DateTime<Utc>,
) -> WorkRecordLink {
    WorkRecordLink {
        link_id: stable_work_link_id(work_id, target_kind, target_id, role),
        work_id: work_id.clone(),
        workspace_id,
        target_kind,
        target_id: Some(target_id.to_string()),
        target_json: None,
        role,
        source: RecordSource::Session,
        fidelity: RecordFidelity::Declared,
        trust: RecordTrust::Low,
        created_at: timestamp,
        updated_at: timestamp,
        schema_version: WORK_OBSERVABILITY_SCHEMA_VERSION,
    }
}

fn base_session_links(
    session: &Session,
    work_id: &WorkRecordId,
    now: DateTime<Utc>,
) -> Vec<WorkRecordLink> {
    vec![
        projection_link(
            session.workspace_id,
            work_id,
            WorkLinkTargetKind::Task,
            &session.task_id.0.to_string(),
            WorkLinkRole::Source,
            now,
        ),
        projection_link(
            session.workspace_id,
            work_id,
            WorkLinkTargetKind::Session,
            &session.id.0.to_string(),
            WorkLinkRole::Source,
            now,
        ),
        projection_link(
            session.workspace_id,
            work_id,
            WorkLinkTargetKind::Worktree,
            &session.worktree_id.0.to_string(),
            WorkLinkRole::Context,
            now,
        ),
    ]
}

fn session_state_events(
    session: &Session,
    work_id: &WorkRecordId,
    now: DateTime<Utc>,
) -> Vec<WorkEvent> {
    let actor_kind = if session.relationship.as_deref() == Some("sub_agent") {
        WorkActorKind::Subagent
    } else {
        WorkActorKind::Agent
    };
    vec![WorkEvent {
        event_id: stable_work_event_id(&format!("session_state:{}", session.id.0)),
        work_id: work_id.clone(),
        workspace_id: session.workspace_id,
        sequence: stable_projector_sequence(&format!("session_state:{}", session.id.0)),
        source_kind: Some(PROJECTOR_SOURCE_KIND.to_string()),
        source_id: Some(session.id.0.to_string()),
        event_type: WorkEventType::Session,
        event_time: session.updated_at,
        actor_kind,
        provider: Some(session.provider_id.clone()),
        harness: Some(session.agent_role.clone()),
        model: Some(session.model_id.clone()),
        redaction_class: WorkRedactionClass::LocalRedacted,
        source: RecordSource::Session,
        fidelity: RecordFidelity::Declared,
        trust: RecordTrust::Low,
        payload_json: None,
        redacted_text: Some(bounded_redacted_text(
            &format!("Session {} status {:?}", session.title, session.status),
            PROJECTOR_TEXT_LIMIT,
        )),
        artifact_ref: None,
        created_at: now,
        schema_version: WORK_OBSERVABILITY_SCHEMA_VERSION,
    }]
}

fn projected_session_event(
    session: &Session,
    work_id: &WorkRecordId,
    event: &SessionEvent,
) -> Option<WorkEvent> {
    let (event_type, actor_kind) = match event.event_type {
        SessionEventType::UserMessage | SessionEventType::InputQueued => {
            (WorkEventType::UserMessage, WorkActorKind::Human)
        }
        SessionEventType::AssistantComplete | SessionEventType::AssistantMessageInserted => {
            (WorkEventType::AssistantMessage, WorkActorKind::Agent)
        }
        SessionEventType::ToolCall => (WorkEventType::ToolCallStart, WorkActorKind::Agent),
        SessionEventType::ToolResult => (WorkEventType::ToolOutput, WorkActorKind::Agent),
        SessionEventType::ArtifactsSet => (WorkEventType::ArtifactCreated, WorkActorKind::Agent),
        SessionEventType::TurnStarted
        | SessionEventType::TurnFinished
        | SessionEventType::TurnInterrupted
        | SessionEventType::Done
        | SessionEventType::Notice
        | SessionEventType::Plan => (WorkEventType::Session, WorkActorKind::Agent),
        _ => return None,
    };

    let actor_kind = if session.relationship.as_deref() == Some("sub_agent")
        && actor_kind == WorkActorKind::Agent
    {
        WorkActorKind::Subagent
    } else {
        actor_kind
    };

    let redacted_text = event_redacted_text(event);
    Some(WorkEvent {
        event_id: stable_work_event_id(&format!("session_event:{}", event.id.0)),
        work_id: work_id.clone(),
        workspace_id: session.workspace_id,
        sequence: event.seq,
        source_kind: Some("session_event".to_string()),
        source_id: Some(event.id.0.to_string()),
        event_type,
        event_time: event.created_at,
        actor_kind,
        provider: Some(session.provider_id.clone()),
        harness: Some(session.agent_role.clone()),
        model: Some(session.model_id.clone()),
        redaction_class: WorkRedactionClass::LocalRedacted,
        source: RecordSource::Session,
        fidelity: RecordFidelity::Exact,
        trust: RecordTrust::Low,
        payload_json: None,
        redacted_text: Some(redacted_text),
        artifact_ref: None,
        created_at: event.created_at,
        schema_version: WORK_OBSERVABILITY_SCHEMA_VERSION,
    })
}

fn event_redacted_text(event: &SessionEvent) -> String {
    let event_label = session_event_type_to_str(&event.event_type);
    let text = extract_text(&event.payload_json).unwrap_or_else(|| {
        ctx_core::redaction::redact_json_value(event.payload_json.clone()).to_string()
    });
    bounded_redacted_text(&format!("{event_label}: {text}"), PROJECTOR_TEXT_LIMIT)
}

fn extract_text(value: &Value) -> Option<String> {
    for pointer in [
        "/content",
        "/message/content",
        "/message",
        "/text",
        "/input",
        "/prompt",
        "/outputText",
        "/output_text",
        "/result",
        "/toolCall/outputText",
        "/toolCall/output_text",
        "/rawOutput/aggregated_output",
        "/rawOutput/output",
    ] {
        if let Some(text) = value.pointer(pointer).and_then(Value::as_str) {
            if !text.trim().is_empty() {
                return Some(text.to_string());
            }
        }
    }
    None
}

fn lifecycle_from_task_status(status: &TaskStatus) -> WorkLifecycle {
    match status {
        TaskStatus::Pending | TaskStatus::Running => WorkLifecycle::Active,
        TaskStatus::Completed => WorkLifecycle::ReadyForReview,
        TaskStatus::Failed => WorkLifecycle::Blocked,
        TaskStatus::Cancelled => WorkLifecycle::Abandoned,
    }
}

fn bounded_redacted_text(value: &str, limit: usize) -> String {
    let redacted = redact_local_paths(ctx_core::redaction::redact_sensitive(value));
    if redacted.len() <= limit {
        return redacted;
    }
    let mut end = 0;
    for (idx, _) in redacted.char_indices() {
        if idx > limit {
            break;
        }
        end = idx;
    }
    format!("{}\n[truncated]", &redacted[..end])
}

fn redact_local_paths(input: String) -> String {
    let mut output = input;
    for marker in [
        "/home/",
        "/Users/",
        "/tmp/",
        "/var/folders/",
        "/private/var/",
        "C:\\Users\\",
        "C:/Users/",
    ] {
        output = redact_path_segments(output, marker);
    }
    output
}

fn redact_path_segments(input: String, marker: &str) -> String {
    let mut output = String::with_capacity(input.len());
    let mut rest = input.as_str();
    while let Some(start) = rest.find(marker) {
        output.push_str(&rest[..start]);
        output.push_str("[redacted:local_path]");
        let matched = &rest[start..];
        let end = matched
            .find(|ch: char| {
                ch.is_whitespace()
                    || matches!(ch, '"' | '\'' | ')' | ']' | '}' | '<' | '>' | ',' | ';')
            })
            .unwrap_or(matched.len());
        rest = &matched[end..];
    }
    output.push_str(rest);
    output
}

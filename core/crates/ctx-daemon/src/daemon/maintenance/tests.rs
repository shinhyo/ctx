use super::*;

use std::collections::HashMap;
use std::sync::Arc;

use chrono::Utc;
use ctx_core::ids::{RunId, TurnId};
use ctx_core::models::{ExecutionEnvironment, Session, SessionTurn, SessionTurnStatus, VcsKind};
use ctx_store::{Store, StoreManager};
use ctx_update_service::route_contract::{
    BeginUpdateDrainRouteRequest, MaintenanceRouteErrorKind, ReleaseUpdateDrainRouteRequest,
    ShutdownDaemonRouteRequest,
};

use crate::daemon::scheduler::SchedulerCommand;

struct EnvVarGuard {
    key: &'static str,
    prev: Option<String>,
}

impl EnvVarGuard {
    fn set(key: &'static str, value: &str) -> Self {
        let prev = std::env::var(key).ok();
        std::env::set_var(key, value);
        Self { key, prev }
    }
}

impl Drop for EnvVarGuard {
    fn drop(&mut self) {
        if let Some(prev) = self.prev.take() {
            std::env::set_var(self.key, prev);
        } else {
            std::env::remove_var(self.key);
        }
    }
}

async fn test_state() -> (tempfile::TempDir, Arc<DaemonState>) {
    test_state_with_shutdown_token(None).await
}

fn sandbox_cli_guard_for_empty_container_list(root: &std::path::Path) -> EnvVarGuard {
    let cli_path = root.join(if cfg!(windows) {
        "sandbox-cli.cmd"
    } else {
        "sandbox-cli.sh"
    });
    write_empty_sandbox_cli(&cli_path);
    EnvVarGuard::set(
        ctx_sandbox_container_runtime::CTX_HARNESS_SANDBOX_CLI_PATH_ENV,
        &cli_path.to_string_lossy(),
    )
}

fn write_empty_sandbox_cli(path: &std::path::Path) {
    #[cfg(windows)]
    {
        std::fs::write(
            path,
            "@echo off\r\nif \"%1\"==\"container\" if \"%2\"==\"ls\" exit /b 0\r\nif \"%1\"==\"info\" (echo {} & exit /b 0)\r\necho unexpected invocation: %* 1>&2\r\nexit /b 1\r\n",
        )
        .unwrap();
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        std::fs::write(
            path,
            "#!/bin/sh\nif [ \"$1\" = \"container\" ] && [ \"$2\" = \"ls\" ]; then\n  exit 0\nfi\nif [ \"$1\" = \"info\" ]; then\n  printf '{}\\n'\n  exit 0\nfi\necho \"unexpected invocation: $*\" >&2\nexit 1\n",
        )
        .unwrap();
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
    }
}

fn begin_update_drain_request(
    confirm: bool,
    reason: Option<String>,
    owner: Option<String>,
) -> BeginUpdateDrainRouteRequest {
    serde_json::from_value(serde_json::json!({
        "confirm": confirm,
        "reason": reason,
        "owner": owner,
    }))
    .expect("valid begin update drain route request")
}

fn release_update_drain_request(confirm: bool) -> ReleaseUpdateDrainRouteRequest {
    serde_json::from_value(serde_json::json!({
        "confirm": confirm,
    }))
    .expect("valid release update drain route request")
}

fn shutdown_daemon_request(
    confirm: bool,
    reason: Option<String>,
    shutdown_token: Option<String>,
) -> ShutdownDaemonRouteRequest {
    serde_json::from_value(serde_json::json!({
        "confirm": confirm,
        "reason": reason,
        "shutdown_token": shutdown_token,
    }))
    .expect("valid shutdown daemon route request")
}

async fn test_state_with_shutdown_token(
    local_shutdown_token: Option<String>,
) -> (tempfile::TempDir, Arc<DaemonState>) {
    let data_dir = tempfile::tempdir().expect("create tempdir");
    let stores = StoreManager::open(data_dir.path())
        .await
        .expect("open stores");
    let mut state = DaemonState::new(
        data_dir.path().to_path_buf(),
        stores,
        HashMap::new(),
        "http://127.0.0.1:0".to_string(),
        None,
    );
    state.core.local_shutdown_token = local_shutdown_token;
    (data_dir, Arc::new(state))
}

async fn insert_turn_with_status(
    state: &Arc<DaemonState>,
    root: &std::path::Path,
    status: SessionTurnStatus,
) {
    let (store, session) = insert_session(state, root).await;
    let now = Utc::now();
    store
        .insert_session_turn(SessionTurn {
            turn_id: TurnId::new(),
            session_id: session.id,
            run_id: Some(RunId::new()),
            user_message_id: None,
            status,
            start_seq: Some(1),
            end_seq: None,
            started_at: now,
            updated_at: now,
            assistant_partial: None,
            thought_partial: None,
            metrics_json: None,
            failure: None,
            tool_total: 0,
            tool_pending: 0,
            tool_running: 0,
            tool_completed: 0,
            tool_failed: 0,
        })
        .await
        .expect("insert turn");
}

async fn insert_session(state: &Arc<DaemonState>, root: &std::path::Path) -> (Store, Session) {
    let workspace = state
        .global_store()
        .create_workspace(
            format!("ws-{}", uuid::Uuid::new_v4()),
            root.join(format!("ws-{}", uuid::Uuid::new_v4()))
                .to_string_lossy()
                .to_string(),
            VcsKind::Git,
        )
        .await
        .expect("create workspace");
    let store = state
        .store_for_workspace(workspace.id)
        .await
        .expect("open workspace store");
    let worktree = store
        .create_worktree(
            workspace.id,
            root.join(format!("worktree-{}", uuid::Uuid::new_v4()))
                .to_string_lossy()
                .to_string(),
            "deadbeef".to_string(),
            None,
        )
        .await
        .expect("create worktree");
    let task = store
        .create_task(workspace.id, "task".to_string(), None)
        .await
        .expect("create task");
    let session = store
        .create_session(
            task.id,
            workspace.id,
            worktree.id,
            ExecutionEnvironment::Host,
            "fake".to_string(),
            "model".to_string(),
            "implementer".to_string(),
            None,
            None,
            None,
        )
        .await
        .expect("create session");
    state
        .global_store()
        .upsert_workspace_session_index(session.id, workspace.id)
        .await
        .expect("index session");
    (store, session)
}

#[tokio::test]
async fn begin_update_drain_acquires_until_released() {
    let (_data_dir, state) = test_state().await;

    let activity = begin_update_drain(&state, "test_update".to_string(), "unit_test".to_string())
        .await
        .expect("idle daemon should acquire update drain");
    assert!(activity.idle);
    assert_eq!(
        post_message_update_drain_reason(&state).await.as_deref(),
        Some("test_update")
    );

    let error = begin_update_drain(&state, "second".to_string(), "unit_test".to_string())
        .await
        .expect_err("second drain should conflict");
    assert!(matches!(error, BeginUpdateDrainError::AlreadyActive));

    assert!(release_update_drain(&state).await);
    assert!(post_message_update_drain_reason(&state).await.is_none());
}

#[tokio::test]
async fn begin_update_drain_route_requires_confirm() {
    let (_data_dir, state) = test_state().await;
    let handle = crate::daemon::route_handles_from_state(&state).update_drain;

    let error = handle
        .begin_update_drain_for_route(begin_update_drain_request(false, None, None))
        .await
        .expect_err("confirm is required");

    assert_eq!(error.kind(), MaintenanceRouteErrorKind::BadRequest);
    assert_eq!(error.message(), "confirm required");
}

#[tokio::test]
async fn begin_update_drain_route_defaults_reason_and_owner() {
    let (_data_dir, state) = test_state().await;
    let handle = crate::daemon::route_handles_from_state(&state).update_drain;

    let result = handle
        .begin_update_drain_for_route(begin_update_drain_request(
            true,
            Some("  ".to_string()),
            Some("".to_string()),
        ))
        .await
        .expect("idle daemon should acquire update drain");

    assert!(result.acquired);
    assert_eq!(
        post_message_update_drain_reason(&state).await.as_deref(),
        Some("daemon_update")
    );
}

#[tokio::test]
async fn begin_update_drain_route_maps_existing_drain_to_conflict() {
    let (_data_dir, state) = test_state().await;
    let handle = crate::daemon::route_handles_from_state(&state).update_drain;
    begin_update_drain(&state, "existing".to_string(), "unit_test".to_string())
        .await
        .expect("acquire initial drain");

    let error = handle
        .begin_update_drain_for_route(begin_update_drain_request(true, None, None))
        .await
        .expect_err("second drain should conflict");

    assert_eq!(error.kind(), MaintenanceRouteErrorKind::Conflict);
    assert_eq!(error.message(), "daemon update drain already active");
}

#[tokio::test]
async fn begin_update_drain_route_rejects_queued_turns() {
    let (data_dir, state) = test_state().await;
    insert_turn_with_status(&state, data_dir.path(), SessionTurnStatus::Queued).await;
    let handle = crate::daemon::route_handles_from_state(&state).update_drain;

    let error = handle
        .begin_update_drain_for_route(begin_update_drain_request(true, None, None))
        .await
        .expect_err("queued turns should keep update drain busy");

    assert_eq!(error.kind(), MaintenanceRouteErrorKind::Conflict);
    assert_eq!(
        error.message(),
        "daemon has queued or running turns; update drain was not acquired"
    );
    assert!(post_message_update_drain_reason(&state).await.is_none());
}

#[tokio::test]
async fn release_update_drain_route_requires_confirm() {
    let (_data_dir, state) = test_state().await;
    let handle = crate::daemon::route_handles_from_state(&state).update_drain;

    let error = handle
        .release_update_drain_for_route(release_update_drain_request(false))
        .await
        .expect_err("confirm is required");

    assert_eq!(error.kind(), MaintenanceRouteErrorKind::BadRequest);
    assert_eq!(error.message(), "confirm required");
}

#[tokio::test]
async fn shutdown_route_rejects_missing_or_invalid_local_token() {
    let (_data_dir, state) = test_state_with_shutdown_token(Some("secret".to_string())).await;
    let handle = crate::daemon::route_handles_from_state(&state).daemon_shutdown;

    for token in [None, Some("wrong".to_string())] {
        let error = handle
            .request_daemon_shutdown_for_route(shutdown_daemon_request(true, None, token))
            .await
            .expect_err("valid local shutdown token is required");

        assert_eq!(error.kind(), MaintenanceRouteErrorKind::Forbidden);
        assert_eq!(error.message(), "local desktop shutdown token required");
    }
}

#[tokio::test]
async fn shutdown_route_interrupts_running_scheduler_sessions() {
    let (data_dir, state) = test_state_with_shutdown_token(Some("secret".to_string())).await;
    let session = insert_session(&state, data_dir.path()).await.1;
    let handle = crate::daemon::route_handles_from_state(&state);
    let (seen_tx, mut seen_rx) = tokio::sync::mpsc::channel(1);
    handle
        .session_message_command
        .ensure_scheduler_for_test(session.clone(), move |_session, mut rx| async move {
            let interrupted = matches!(rx.recv().await, Some(SchedulerCommand::Interrupt(_)));
            let _ = seen_tx.send(interrupted).await;
        })
        .await;
    state
        .task_session_cleanup
        .set_running(session.id, true)
        .await;

    let result = handle
        .daemon_shutdown
        .request_daemon_shutdown_for_route(shutdown_daemon_request(
            true,
            Some("unit_test_shutdown".to_string()),
            Some("secret".to_string()),
        ))
        .await
        .expect("shutdown should be accepted");

    assert!(result.accepted);
    assert_eq!(
        tokio::time::timeout(std::time::Duration::from_secs(1), seen_rx.recv())
            .await
            .expect("scheduler should receive shutdown interrupt"),
        Some(true)
    );
}

#[tokio::test]
async fn shutdown_route_tolerates_running_sessions_without_scheduler_sender() {
    let (data_dir, state) = test_state_with_shutdown_token(Some("secret".to_string())).await;
    let session = insert_session(&state, data_dir.path()).await.1;
    state
        .task_session_cleanup
        .set_running(session.id, true)
        .await;
    let handle = crate::daemon::route_handles_from_state(&state).daemon_shutdown;

    let result = handle
        .request_daemon_shutdown_for_route(shutdown_daemon_request(
            true,
            Some("unit_test_shutdown".to_string()),
            Some("secret".to_string()),
        ))
        .await
        .expect("shutdown should not require every running session to have a scheduler sender");

    assert!(result.accepted);
}

#[tokio::test]
async fn execution_reject_uses_update_drain_owner() {
    let (_data_dir, state) = test_state().await;
    begin_update_drain(&state, "test_update".to_string(), "unit_test".to_string())
        .await
        .expect("acquire drain");

    let error = reject_new_execution_during_maintenance(&state)
        .await
        .expect_err("drain should reject new execution");
    assert!(error.to_string().contains("test_update"));
}

#[tokio::test]
async fn linux_sandbox_prepare_drain_conflicts_with_existing_drain() {
    let (_data_dir, state) = test_state().await;
    begin_update_drain(&state, "test_update".to_string(), "unit_test".to_string())
        .await
        .expect("acquire drain");

    let error = match acquire_linux_sandbox_prepare_drain(&state).await {
        Ok(_) => panic!("active maintenance drain should reject sandbox prepare"),
        Err(error) => error,
    };
    assert!(matches!(error, MaintenanceDrainError::AlreadyActive));
}

#[tokio::test]
async fn linux_sandbox_prepare_drain_drop_releases_drain() {
    let _serial = crate::test_support::sandbox_cli_env_test_lock()
        .lock()
        .await;
    let (data_dir, state) = test_state().await;
    let _sandbox_cli = sandbox_cli_guard_for_empty_container_list(data_dir.path());
    let permit = acquire_linux_sandbox_prepare_drain(&state)
        .await
        .expect("idle daemon should acquire sandbox prepare drain");
    assert_eq!(
        post_message_update_drain_reason(&state).await.as_deref(),
        Some("linux_sandbox_runtime_prepare")
    );

    drop(permit);

    for _ in 0..20 {
        if post_message_update_drain_reason(&state).await.is_none() {
            return;
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    panic!("dropping maintenance drain permit should release the drain");
}

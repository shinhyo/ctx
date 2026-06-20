use std::collections::HashMap;

use anyhow::Result;
use ctx_core::ids::RunId;
use ctx_core::models::{ExecutionEnvironment, Session};
use ctx_harness_sources::HarnessSourceKind;
use ctx_sandbox_contract::ContainerNetworkMode;

pub(super) struct ProviderTurnAdmissionEnvRequest<'a> {
    pub(super) store: &'a ctx_store::Store,
    pub(super) session: &'a Session,
    pub(super) run_id: RunId,
    pub(super) provider_id: &'a str,
    pub(super) model_id: &'a str,
    pub(super) execution_environment: ExecutionEnvironment,
    pub(super) container_network_mode: ContainerNetworkMode,
    pub(super) source_kind: HarnessSourceKind,
}

pub(super) async fn apply_provider_turn_admission_env(
    provider_env: &mut HashMap<String, String>,
    request: ProviderTurnAdmissionEnvRequest<'_>,
) -> Result<()> {
    let _ = (
        provider_env,
        request.store,
        request.session,
        request.run_id,
        request.provider_id,
        request.model_id,
        request.execution_environment,
        request.container_network_mode,
        request.source_kind,
    );
    Ok(())
}

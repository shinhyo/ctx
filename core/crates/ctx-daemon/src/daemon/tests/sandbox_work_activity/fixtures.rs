use super::*;

pub(super) struct SandboxWorkActivityFixture {
    state: Arc<DaemonState>,
    temp: tempfile::TempDir,
    _sandbox_cli_override: EnvVarGuard,
    _serial: tokio::sync::MutexGuard<'static, ()>,
}

impl SandboxWorkActivityFixture {
    pub(super) async fn new() -> Self {
        let serial = sandbox_cli_env_test_lock().lock().await;
        let temp = tempdir().unwrap();
        let cli_path = temp.path().join(if cfg!(windows) {
            "sandbox-cli.cmd"
        } else {
            "sandbox-cli.sh"
        });
        write_empty_sandbox_cli(&cli_path);
        let sandbox_cli_override = EnvVarGuard::set(
            CTX_HARNESS_SANDBOX_CLI_PATH_ENV,
            &cli_path.to_string_lossy(),
        );
        let stores = StoreManager::open(temp.path()).await.unwrap();
        let state = Arc::new(DaemonState::new(
            temp.path().to_path_buf(),
            stores,
            HashMap::new(),
            "http://localhost".to_string(),
            None,
        ));

        Self {
            state,
            temp,
            _sandbox_cli_override: sandbox_cli_override,
            _serial: serial,
        }
    }

    pub(super) fn state(&self) -> Arc<DaemonState> {
        self.state.clone()
    }

    pub(super) fn root(&self) -> &std::path::Path {
        self.temp.path()
    }
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
        std::fs::write(
            path,
            "#!/bin/sh\nif [ \"$1\" = \"container\" ] && [ \"$2\" = \"ls\" ]; then\n  exit 0\nfi\nif [ \"$1\" = \"info\" ]; then\n  printf '{}\\n'\n  exit 0\nfi\necho \"unexpected invocation: $*\" >&2\nexit 1\n",
        )
        .unwrap();
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
    }
}

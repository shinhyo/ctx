use std::{
    collections::BTreeMap,
    io,
    net::{Ipv4Addr, SocketAddr},
    path::{Path, PathBuf},
    process::Command,
    str::FromStr,
};

use anyhow::{anyhow, Result};
use ctx_history_core::{database_path, CaptureProvider, EventType};
use ctx_history_search::{search_packet, PacketOptions, SearchFilters};
use ctx_history_store::Store;
use include_dir::{include_dir, Dir, File};
use rusqlite::Connection;
use serde_json::{json, Value};
use tiny_http::{Header, Method, Request, Response, Server, StatusCode};
use url::form_urlencoded;
use uuid::Uuid;

const MAX_WEB_LIMIT: usize = 200;
const COOKIE_NAME: &str = "ctx_web_token";
static SEARCH_WEB_DIST: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/web/search-ui/dist");

pub(crate) fn serve_web(data_root: PathBuf, args: crate::WebArgs) -> Result<()> {
    let addr = bind_addr(&args.host, args.port)?;
    let server =
        Server::http(addr).map_err(|err| anyhow!("failed to start ctx web server: {err}"))?;
    let token = launch_token();
    let listen_addr = server.server_addr().to_string();
    let url = format!("http://{listen_addr}/");
    println!("ctx web listening on {url}");
    println!("Press Ctrl-C to stop.");
    if args.open {
        open_browser(&url);
    }

    for request in server.incoming_requests() {
        if let Err(err) = handle_request(request, &data_root, &token) {
            eprintln!("warning: web search request failed: {err}");
        }
    }
    Ok(())
}

fn handle_request(request: Request, data_root: &Path, token: &str) -> Result<()> {
    let method = request.method().clone();
    let url = request.url().to_owned();
    let (path, query) = split_url(&url);
    let params = query_params(query);

    match (method, path) {
        (Method::Get, "/api/search") => {
            if !is_authorized(&request, &params, token) {
                return respond(
                    request,
                    text_response("forbidden", StatusCode(403), "text/plain"),
                );
            }
            let value = search_response(data_root, &params)?;
            respond(request, json_response(value))
        }
        (Method::Get, "/api/filter-options") => {
            if !is_authorized(&request, &params, token) {
                return respond(
                    request,
                    text_response("forbidden", StatusCode(403), "text/plain"),
                );
            }
            let value = filter_options_response(data_root)?;
            respond(request, json_response(value))
        }
        (Method::Get, "/health") => respond(request, json_response(json!({ "ok": true }))),
        (Method::Get, _) => {
            if let Some(asset_path) = static_asset_path(path) {
                if let Some(file) = SEARCH_WEB_DIST.get_file(asset_path) {
                    let response = if matches!(path, "/" | "/index.html") {
                        asset_response_with_cookie(file, token)
                    } else {
                        asset_response(file)
                    };
                    return respond(request, response);
                }
            }
            respond(
                request,
                text_response("not found", StatusCode(404), "text/plain"),
            )
        }
        _ => respond(
            request,
            text_response("not found", StatusCode(404), "text/plain"),
        ),
    }
}

fn static_asset_path(path: &str) -> Option<&str> {
    let asset_path = match path {
        "/" | "/index.html" => "index.html",
        _ => path.trim_start_matches('/'),
    };
    if asset_path.is_empty()
        || asset_path.starts_with('.')
        || asset_path.contains("..")
        || asset_path.contains('\\')
    {
        return None;
    }
    Some(asset_path)
}

fn search_response(data_root: &Path, params: &BTreeMap<String, String>) -> Result<Value> {
    let store = Store::open(database_path(data_root.to_path_buf()))?;
    let query = params.get("q").cloned().unwrap_or_default();
    let options = PacketOptions {
        limit: search_limit(params),
        filters: web_filters(params, &store)?,
        ..PacketOptions::default()
    };
    let packet = search_packet(&store, &query, &options)?;
    let refresh = crate::SearchRefreshReport::skipped(crate::RefreshArg::Off, "web_existing_index");
    Ok(crate::SearchDto::packet(
        &store,
        &packet,
        &refresh,
        Some(&query),
    ))
}

fn filter_options_response(data_root: &Path) -> Result<Value> {
    let db_path = database_path(data_root.to_path_buf());
    let store = Store::open(&db_path)?;
    let conn = Connection::open(store.path())?;
    Ok(json!({
        "repos": option_values(&conn, REPO_OPTIONS_SQL, 100)?,
        "files": option_values(&conn, FILE_OPTIONS_SQL, 250)?,
        "event_types": event_type_options(),
    }))
}

const REPO_OPTIONS_SQL: &str = r#"
SELECT value
FROM (
    SELECT root_path AS value, updated_at_ms AS sort_key
    FROM vcs_workspaces
    WHERE root_path IS NOT NULL AND trim(root_path) != ''
    UNION ALL
    SELECT name AS value, updated_at_ms AS sort_key
    FROM vcs_workspaces
    WHERE name IS NOT NULL AND trim(name) != ''
    UNION ALL
    SELECT owner || '/' || name AS value, updated_at_ms AS sort_key
    FROM vcs_workspaces
    WHERE owner IS NOT NULL AND trim(owner) != '' AND name IS NOT NULL AND trim(name) != ''
    UNION ALL
    SELECT workspace AS value, last_activity_at_ms AS sort_key
    FROM history_records
    WHERE workspace IS NOT NULL AND trim(workspace) != ''
    UNION ALL
    SELECT cwd AS value, started_at_ms AS sort_key
    FROM capture_sources
    WHERE cwd IS NOT NULL AND trim(cwd) != ''
)
GROUP BY value
ORDER BY max(sort_key) DESC, value
LIMIT ?1
"#;

const FILE_OPTIONS_SQL: &str = r#"
SELECT value
FROM (
    SELECT path AS value, updated_at_ms AS sort_key
    FROM files_touched
    WHERE trim(path) != ''
    UNION ALL
    SELECT old_path AS value, updated_at_ms AS sort_key
    FROM files_touched
    WHERE old_path IS NOT NULL AND trim(old_path) != ''
)
GROUP BY value
ORDER BY max(sort_key) DESC, value
LIMIT ?1
"#;

fn option_values(conn: &Connection, sql: &str, limit: usize) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map([limit as i64], |row| row.get::<_, String>(0))?;
    let mut values = Vec::new();
    for row in rows {
        values.push(row?);
    }
    Ok(values)
}

fn event_type_options() -> Vec<Value> {
    [
        ("message", "Message"),
        ("tool_call", "Tool call"),
        ("tool_output", "Tool output"),
        ("command_started", "Command started"),
        ("command_output", "Command output"),
        ("command_finished", "Command finished"),
        ("file_touched", "File touched"),
        ("vcs_change", "VCS change"),
        ("artifact", "Artifact"),
        ("summary", "Summary"),
        ("notice", "Notice"),
    ]
    .into_iter()
    .map(|(value, label)| json!({ "value": value, "label": label }))
    .collect()
}

fn web_filters(params: &BTreeMap<String, String>, store: &Store) -> Result<SearchFilters> {
    let primary_only = bool_param(params, "primary_only");
    let include_subagents = if params.contains_key("include_subagents") {
        bool_param(params, "include_subagents")
    } else {
        !primary_only
    };
    Ok(SearchFilters {
        session: None,
        provider: params
            .get("provider")
            .filter(|value| !value.trim().is_empty())
            .map(|value| CaptureProvider::from_str(value.trim()))
            .transpose()
            .map_err(|err| anyhow!("{err}"))?,
        repo: params
            .get("repo")
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty()),
        since: params
            .get("since")
            .map(|value| value.trim())
            .filter(|value| !value.is_empty())
            .map(crate::parse_since_filter)
            .transpose()?,
        until: params
            .get("until")
            .map(|value| value.trim())
            .filter(|value| !value.is_empty())
            .map(|value| crate::parse_time_filter(value, "--until"))
            .transpose()?,
        primary_only,
        include_subagents,
        event_type: params
            .get("event_type")
            .map(|value| value.trim())
            .filter(|value| !value.is_empty())
            .map(EventType::from_str)
            .transpose()
            .map_err(|err| anyhow!("{err}"))?,
        file: params
            .get("file")
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty()),
        exclude_provider_session: crate::current_codex_provider_session_filter(Some(store)),
    })
}

fn search_limit(params: &BTreeMap<String, String>) -> usize {
    params
        .get("limit")
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(20)
        .clamp(1, MAX_WEB_LIMIT)
}

fn bool_param(params: &BTreeMap<String, String>, key: &str) -> bool {
    matches!(
        params.get(key).map(|value| value.as_str()),
        Some("1" | "true" | "yes" | "on")
    )
}

fn launch_token() -> String {
    std::env::var("CTX_SEARCH_WEB_TOKEN")
        .ok()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple()))
}

fn bind_addr(host: &str, port: u16) -> Result<SocketAddr> {
    if host != "127.0.0.1" {
        return Err(anyhow!(
            "ctx web only binds 127.0.0.1; remove --host or pass --host 127.0.0.1"
        ));
    }
    Ok(SocketAddr::new(Ipv4Addr::LOCALHOST.into(), port))
}

fn split_url(url: &str) -> (&str, &str) {
    url.split_once('?').unwrap_or((url, ""))
}

fn query_params(query: &str) -> BTreeMap<String, String> {
    form_urlencoded::parse(query.as_bytes())
        .into_owned()
        .collect::<BTreeMap<_, _>>()
}

fn token_matches(params: &BTreeMap<String, String>, token: &str) -> bool {
    params.get("token").map(|value| value.as_str()) == Some(token)
}

fn is_authorized(request: &Request, params: &BTreeMap<String, String>, token: &str) -> bool {
    token_matches(params, token) || request_has_cookie_token(request, token)
}

fn request_has_cookie_token(request: &Request, token: &str) -> bool {
    request.headers().iter().any(|header| {
        header.field.equiv("Cookie") && cookie_header_has_token(header.value.as_str(), token)
    })
}

fn cookie_header_has_token(header: &str, token: &str) -> bool {
    header.split(';').any(|part| {
        part.trim()
            .split_once('=')
            .is_some_and(|(name, value)| name.trim() == COOKIE_NAME && value.trim() == token)
    })
}

fn open_browser(url: &str) {
    let mut command = if cfg!(target_os = "macos") {
        let mut command = Command::new("open");
        command.arg(url);
        command
    } else if cfg!(target_os = "windows") {
        let mut command = Command::new("cmd");
        command.args(["/C", "start", "", url]);
        command
    } else {
        let mut command = Command::new("xdg-open");
        command.arg(url);
        command
    };
    if let Err(err) = command.spawn() {
        eprintln!("warning: failed to open browser: {err}");
    }
}

fn respond(request: Request, response: Response<io::Cursor<Vec<u8>>>) -> Result<()> {
    request
        .respond(response)
        .map_err(|err| anyhow!("failed to write response: {err}"))
}

fn json_response(value: Value) -> Response<io::Cursor<Vec<u8>>> {
    text_response(
        serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_owned()),
        StatusCode(200),
        "application/json; charset=utf-8",
    )
}

fn text_response(
    body: impl Into<String>,
    status: StatusCode,
    content_type: &'static str,
) -> Response<io::Cursor<Vec<u8>>> {
    Response::from_string(body.into())
        .with_status_code(status)
        .with_header(Header::from_bytes("Content-Type", content_type).unwrap())
        .with_header(Header::from_bytes("Cache-Control", "no-store").unwrap())
        .with_header(Header::from_bytes("Referrer-Policy", "no-referrer").unwrap())
        .with_header(Header::from_bytes("X-Content-Type-Options", "nosniff").unwrap())
        .with_header(Header::from_bytes("Content-Security-Policy", csp()).unwrap())
}

fn asset_response(file: &File<'_>) -> Response<io::Cursor<Vec<u8>>> {
    Response::from_data(file.contents().to_vec())
        .with_status_code(StatusCode(200))
        .with_header(Header::from_bytes("Content-Type", mime_type(file.path())).unwrap())
        .with_header(Header::from_bytes("Cache-Control", "no-store").unwrap())
        .with_header(Header::from_bytes("Referrer-Policy", "no-referrer").unwrap())
        .with_header(Header::from_bytes("X-Content-Type-Options", "nosniff").unwrap())
        .with_header(Header::from_bytes("Content-Security-Policy", csp()).unwrap())
}

fn asset_response_with_cookie(file: &File<'_>, token: &str) -> Response<io::Cursor<Vec<u8>>> {
    asset_response(file).with_header(
        Header::from_bytes(
            "Set-Cookie",
            format!("{COOKIE_NAME}={token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=86400"),
        )
        .unwrap(),
    )
}

fn csp() -> &'static str {
    "default-src 'self'; connect-src 'self'; img-src 'self' data:; font-src 'self' data:; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
}

fn mime_type(path: &Path) -> &'static str {
    match path.extension().and_then(|value| value.to_str()) {
        Some("css") => "text/css; charset=utf-8",
        Some("html") => "text/html; charset=utf-8",
        Some("js") => "text/javascript; charset=utf-8",
        Some("json") => "application/json; charset=utf-8",
        Some("svg") => "image/svg+xml",
        Some("woff2") => "font/woff2",
        _ => "application/octet-stream",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bind_addr_rejects_non_loopback() {
        assert!(bind_addr("127.0.0.1", 0).is_ok());
        assert!(bind_addr("0.0.0.0", 0).is_err());
    }

    #[test]
    fn index_asset_contains_built_app_and_no_external_hosts() {
        let index = SEARCH_WEB_DIST
            .get_file("index.html")
            .and_then(|file| std::str::from_utf8(file.contents()).ok())
            .unwrap();
        assert!(index.contains("ctx search"));
        assert!(index.contains("/assets/"));
        assert!(!index.contains("https://"));
        assert!(!index.contains("http://"));
    }

    #[test]
    fn static_asset_path_normalizes_index_and_rejects_traversal() {
        assert_eq!(static_asset_path("/"), Some("index.html"));
        assert_eq!(static_asset_path("/index.html"), Some("index.html"));
        assert_eq!(static_asset_path("/assets/app.js"), Some("assets/app.js"));
        assert_eq!(static_asset_path("/../secret"), None);
        assert_eq!(static_asset_path("/assets\\secret"), None);
    }

    #[test]
    fn token_gate_accepts_query_token_or_cookie_token() {
        let params = query_params("token=abc&q=test");
        assert!(token_matches(&params, "abc"));
        assert!(!token_matches(&params, "def"));
        assert!(cookie_header_has_token("other=1; ctx_web_token=abc", "abc"));
        assert!(!cookie_header_has_token("ctx_web_token=abc", "def"));
    }

    #[test]
    fn web_filters_preserve_explicit_subagent_toggle() {
        let temp = tempfile::tempdir().unwrap();
        let store = Store::open(database_path(temp.path().to_path_buf())).unwrap();
        let filters = web_filters(
            &query_params(
                "include_subagents=false&since=2026-06-01T00%3A00%3A00Z&until=2026-06-02T00%3A00%3A00Z",
            ),
            &store,
        )
        .unwrap();
        assert!(!filters.primary_only);
        assert!(!filters.include_subagents);
        assert_eq!(
            filters.since.unwrap().to_rfc3339(),
            "2026-06-01T00:00:00+00:00"
        );
        assert_eq!(
            filters.until.unwrap().to_rfc3339(),
            "2026-06-02T00:00:00+00:00"
        );

        let filters = web_filters(&query_params("primary_only=true"), &store).unwrap();
        assert!(filters.primary_only);
        assert!(!filters.include_subagents);

        let filters = web_filters(&query_params("primary_only=false"), &store).unwrap();
        assert!(!filters.primary_only);
        assert!(filters.include_subagents);
    }

    #[test]
    fn filter_options_include_guided_event_types() {
        let temp = tempfile::tempdir().unwrap();
        let value = filter_options_response(temp.path()).unwrap();
        assert!(value["repos"].as_array().is_some());
        assert!(value["files"].as_array().is_some());
        let event_types = value["event_types"].as_array().unwrap();
        assert!(event_types.iter().any(|event_type| {
            event_type["value"] == "tool_call" && event_type["label"] == "Tool call"
        }));
    }

    #[test]
    fn filter_options_include_capture_source_cwd() {
        let temp = tempfile::tempdir().unwrap();
        let db_path = database_path(temp.path().to_path_buf());
        let _store = Store::open(&db_path).unwrap();
        let conn = Connection::open(db_path).unwrap();
        conn.execute(
            r#"
            INSERT INTO capture_sources
                (id, kind, provider, machine_id, cwd, started_at_ms, fidelity, visibility, sync_state, sync_version, metadata_json)
            VALUES
                (?1, 'provider_import', 'codex', 'test-machine', ?2, 1782259200000, 'imported', 'local_only', 'local_only', 0, '{}')
            "#,
            [
                Uuid::parse_str("018f45d0-0000-7000-8000-000000000001")
                    .unwrap()
                    .to_string(),
                "/workspace/from-capture-source".to_owned(),
            ],
        )
        .unwrap();

        let value = filter_options_response(temp.path()).unwrap();
        let repos = value["repos"].as_array().unwrap();
        assert!(repos
            .iter()
            .any(|repo| repo.as_str() == Some("/workspace/from-capture-source")));
    }
}

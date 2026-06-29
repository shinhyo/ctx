#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'perf smoke failed: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
usage: scripts/perf-smoke.sh

Runs an offline ctx CLI performance smoke against a generated Codex session
corpus. Set CTX_PERF_SMOKE_BIN to use an existing ctx binary; otherwise the
script builds target/debug/ctx first.

Common overrides:
  CTX_PERF_SMOKE_SESSIONS=2000
  CTX_PERF_SMOKE_REPEATS=5
  CTX_PERF_SMOKE_CHANGED_FILES=5
  CTX_PERF_SMOKE_STATUS_P95_MS=750
  CTX_PERF_SMOKE_SEARCH_P95_MS=2500
  CTX_PERF_SMOKE_IMPORT_NOOP_P95_MS=2500
  CTX_PERF_SMOKE_IMPORT_CHANGED_P95_MS=3000
  CTX_PERF_SMOKE_SHOW_SESSION_P95_MS=1500
  CTX_PERF_SMOKE_ENFORCE=0
USAGE
}

find_repo_root() {
  local candidate
  for candidate in "${BUILD_WORKSPACE_DIRECTORY:-}" "$(pwd)" "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; do
    if [[ -n "${candidate}" && -f "${candidate}/Cargo.toml" ]]; then
      cd "${candidate}"
      pwd
      return 0
    fi
  done
  fail 'could not locate repo root containing Cargo.toml'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if (( "$#" > 0 )); then
  usage >&2
  exit 2
fi

command -v python3 >/dev/null 2>&1 || fail 'python3 is required'

repo_root="$(find_repo_root)"
cd "${repo_root}"

ctx_bin="${CTX_PERF_SMOKE_BIN:-}"
if [[ -z "${ctx_bin}" ]]; then
  printf '==> cargo build --quiet --locked -p ctx --bin ctx\n'
  cargo build --quiet --locked -p ctx --bin ctx
  ctx_bin="${repo_root}/target/debug/ctx"
fi

[[ -x "${ctx_bin}" ]] || fail "ctx binary is not executable: ${ctx_bin}"

export CTX_PERF_SMOKE_BIN="${ctx_bin}"
python3 - "${repo_root}" "${ctx_bin}" <<'PY'
from __future__ import annotations

import datetime as dt
import json
import math
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(sys.argv[1]).resolve()
CTX_BIN = Path(sys.argv[2]).resolve()
QUERY = "perfneedle"


class HarnessError(Exception):
    pass


def env_flag(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() not in {"", "0", "false", "no", "off"}


def env_int(name: str, default: int, minimum: int = 1) -> int:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        value = int(raw)
    except ValueError as exc:
        raise HarnessError(f"{name} must be an integer, got {raw!r}") from exc
    if value < minimum:
        raise HarnessError(f"{name} must be at least {minimum}, got {value}")
    return value


def env_float(name: str, default: float, minimum: float = 0.0) -> float:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        value = float(raw)
    except ValueError as exc:
        raise HarnessError(f"{name} must be a number, got {raw!r}") from exc
    if value < minimum:
        raise HarnessError(f"{name} must be at least {minimum}, got {value}")
    return value


def round2(value: float) -> float:
    return round(value, 2)


def percentile(sorted_samples: list[float], pct: float) -> float:
    if not sorted_samples:
        raise HarnessError("cannot compute percentile for empty samples")
    index = math.ceil((len(sorted_samples) - 1) * (pct / 100.0))
    return sorted_samples[min(index, len(sorted_samples) - 1)]


def timing_stats(samples: list[float]) -> dict[str, object]:
    sorted_samples = sorted(samples)
    return {
        "sample_count": len(samples),
        "samples_ms": [round2(sample) for sample in samples],
        "p50_ms": round2(percentile(sorted_samples, 50.0)),
        "p95_ms": round2(percentile(sorted_samples, 95.0)),
        "min_ms": round2(sorted_samples[0]),
        "max_ms": round2(sorted_samples[-1]),
    }


def safe_recreate_dir(path: Path) -> None:
    resolved = path.resolve()
    forbidden = {Path("/").resolve(), REPO_ROOT, REPO_ROOT.parent}
    home = Path.home().resolve()
    forbidden.add(home)
    if resolved in forbidden:
        raise HarnessError(f"refusing to delete unsafe work directory: {resolved}")
    if resolved.exists():
        shutil.rmtree(resolved)
    resolved.mkdir(parents=True, exist_ok=True)


def json_line(value: object) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True) + "\n"


def timestamp(index: int, event_index: int) -> str:
    base = dt.datetime(2026, 6, 26, tzinfo=dt.timezone.utc)
    instant = base + dt.timedelta(seconds=index % 86_400, milliseconds=event_index)
    return instant.strftime("%Y-%m-%dT%H:%M:%S.") + f"{instant.microsecond // 1000:03d}Z"


def session_path(corpus_root: Path, index: int) -> Path:
    shard = f"{index // 1000:02d}"
    return corpus_root / "2026" / "06" / "26" / shard / f"synthetic-session-{index:06d}.jsonl"


def generated_lines(index: int, marker: str) -> list[str]:
    session_id = f"synthetic-codex-session-{index:06d}"
    cwd = "/workspace/ctx"
    return [
        json_line(
            {
                "timestamp": timestamp(index, 0),
                "type": "session_meta",
                "payload": {
                    "id": session_id,
                    "timestamp": timestamp(index, 0),
                    "cwd": cwd,
                    "originator": "codex-cli",
                    "cli_version": "0.2.0-perf-smoke",
                    "source": "cli",
                    "model_provider": "openai",
                },
            }
        ),
        json_line(
            {
                "timestamp": timestamp(index, 1),
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "user",
                    "content": [
                        {
                            "type": "input_text",
                            "text": f"{QUERY} generated ctx perf smoke corpus session {index:06d} {marker}",
                        }
                    ],
                },
            }
        ),
        json_line(
            {
                "timestamp": timestamp(index, 2),
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        {
                            "type": "output_text",
                            "text": f"Indexing deterministic performance fixture {index:06d}.",
                        }
                    ],
                    "phase": "commentary",
                },
            }
        ),
        json_line(
            {
                "timestamp": timestamp(index, 3),
                "type": "response_item",
                "payload": {
                    "type": "function_call",
                    "name": "exec_command",
                    "arguments": json.dumps(
                        {
                            "cmd": f"cargo test -p ctx synthetic_perf_{index:06d}",
                            "workdir": cwd,
                            "yield_time_ms": 1000,
                        },
                        separators=(",", ":"),
                    ),
                    "call_id": f"call-perf-{index:06d}",
                },
            }
        ),
        json_line(
            {
                "timestamp": timestamp(index, 4),
                "type": "event_msg",
                "payload": {
                    "type": "task_complete",
                    "last_agent_message": f"{QUERY} completed generated fixture session {index:06d}.",
                },
            }
        ),
    ]


def generate_corpus(corpus_root: Path, sessions: int) -> tuple[int, int]:
    bytes_written = 0
    events = 0
    for index in range(sessions):
        path = session_path(corpus_root, index)
        path.parent.mkdir(parents=True, exist_ok=True)
        body = "".join(generated_lines(index, "baseline"))
        path.write_text(body, encoding="utf-8")
        bytes_written += len(body.encode("utf-8"))
        events += 4
    return bytes_written, events


def append_changed_events(corpus_root: Path, sessions: int, changed_files: int, sample: int) -> None:
    for offset in range(changed_files):
        index = (sample * changed_files + offset) % sessions
        path = session_path(corpus_root, index)
        line = json_line(
            {
                "timestamp": timestamp(index, 100 + sample),
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "user",
                    "content": [
                        {
                            "type": "input_text",
                            "text": (
                                f"{QUERY} changed incremental import sample {sample:02d} "
                                f"file {offset:02d} session {index:06d}"
                            ),
                        }
                    ],
                },
            }
        )
        with path.open("a", encoding="utf-8") as handle:
            handle.write(line)


def command_env(home: Path, data_root: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home),
            "CTX_DATA_ROOT": str(data_root),
            "CTX_ANALYTICS_OFF": "1",
        }
    )
    env.pop("CODEX_THREAD_ID", None)
    return env


def run_ctx(args: list[str], env: dict[str, str]) -> tuple[float, dict[str, object], str]:
    started = time.perf_counter()
    completed = subprocess.run(
        [str(CTX_BIN), *args],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    elapsed_ms = (time.perf_counter() - started) * 1000.0
    if completed.returncode != 0:
        raise HarnessError(
            "ctx command failed\n"
            f"command: {command_string(args)}\n"
            f"exit: {completed.returncode}\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )
    try:
        parsed = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise HarnessError(
            f"ctx command did not return JSON: {command_string(args)}\n{completed.stdout}"
        ) from exc
    return elapsed_ms, parsed, completed.stderr


def command_string(args: list[str]) -> str:
    rendered = [str(CTX_BIN), *args]
    return " ".join(rendered)


def measure(
    label: str,
    args: list[str],
    repeats: int,
    env: dict[str, str],
    validate,
) -> tuple[dict[str, object], dict[str, object]]:
    samples: list[float] = []
    last: dict[str, object] | None = None
    for _ in range(repeats):
        elapsed_ms, packet, _ = run_ctx(args, env)
        validate(packet)
        samples.append(elapsed_ms)
        last = packet
    if last is None:
        raise HarnessError(f"{label} collected no samples")
    return {
        "command": command_string(args),
        "timings": timing_stats(samples),
    }, last


def expect_import_totals(packet: dict[str, object]) -> dict[str, int]:
    totals = packet.get("totals")
    if not isinstance(totals, dict):
        raise HarnessError(f"import output is missing totals: {packet}")
    failed = int(totals.get("failed", 0))
    failed_sources = int(totals.get("failed_sources", 0))
    if failed or failed_sources:
        raise HarnessError(f"import reported failures: {totals}")
    return {key: int(value) for key, value in totals.items() if isinstance(value, int)}


def profile_summary(packet: dict[str, object]) -> dict[str, object]:
    totals = expect_import_totals(packet)
    return {
        "source_files": totals.get("source_files", 0),
        "source_bytes": totals.get("source_bytes", 0),
        "imported_sessions": totals.get("imported_sessions", 0),
        "imported_events": totals.get("imported_events", 0),
        "imported_edges": totals.get("imported_edges", 0),
        "skipped": totals.get("skipped", 0),
    }


def db_footprint_bytes(data_root: Path) -> int:
    total = 0
    for suffix in ["work.sqlite", "work.sqlite-wal", "work.sqlite-shm"]:
        path = data_root / suffix
        if path.exists():
            total += path.stat().st_size
    return total


def main() -> int:
    sessions = env_int("CTX_PERF_SMOKE_SESSIONS", 2000)
    repeats = env_int("CTX_PERF_SMOKE_REPEATS", 5)
    changed_files = min(env_int("CTX_PERF_SMOKE_CHANGED_FILES", 5), sessions)
    enforce = env_flag("CTX_PERF_SMOKE_ENFORCE", True)
    work_dir = Path(os.environ.get("CTX_PERF_SMOKE_WORK_DIR", REPO_ROOT / "target" / "ctx-perf-smoke"))
    default_artifact_dir = Path(
        os.environ.get(
            "TEST_UNDECLARED_OUTPUTS_DIR",
            REPO_ROOT / "target" / "ctx-artifacts" / "perf-smoke",
        )
    )
    artifact_path = Path(
        os.environ.get(
            "CTX_PERF_SMOKE_ARTIFACT",
            default_artifact_dir / "ctx-cli-perf-smoke.json",
        )
    )
    thresholds = {
        "status_p95_ms": env_float("CTX_PERF_SMOKE_STATUS_P95_MS", 750.0),
        "search_p95_ms": env_float("CTX_PERF_SMOKE_SEARCH_P95_MS", 2500.0),
        "import_noop_p95_ms": env_float("CTX_PERF_SMOKE_IMPORT_NOOP_P95_MS", 2500.0),
        "import_changed_p95_ms": env_float("CTX_PERF_SMOKE_IMPORT_CHANGED_P95_MS", 3000.0),
        "show_session_p95_ms": env_float("CTX_PERF_SMOKE_SHOW_SESSION_P95_MS", 1500.0),
    }

    safe_recreate_dir(work_dir)
    home = work_dir / "home"
    data_root = work_dir / "data"
    corpus_root = work_dir / "corpus" / "codex-sessions"
    home.mkdir(parents=True, exist_ok=True)
    data_root.mkdir(parents=True, exist_ok=True)

    env = command_env(home, data_root)

    generation_started = time.perf_counter()
    source_bytes, generated_events = generate_corpus(corpus_root, sessions)
    generation_ms = (time.perf_counter() - generation_started) * 1000.0

    version = subprocess.run(
        [str(CTX_BIN), "--version"],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout.strip()

    initial_import_ms, initial_import_packet, _ = run_ctx(
        ["import", "--provider", "codex", "--path", str(corpus_root), "--json", "--progress", "none"],
        env,
    )
    initial_totals = profile_summary(initial_import_packet)
    if initial_totals["imported_sessions"] != sessions:
        raise HarnessError(
            f"initial import expected {sessions} sessions, got {initial_totals['imported_sessions']}"
        )
    if initial_totals["imported_events"] <= 0:
        raise HarnessError("initial import produced no events")

    status_profile, status_last = measure(
        "status",
        ["status", "--json"],
        repeats,
        env,
        lambda packet: (
            packet.get("initialized") is True
            or (_ for _ in ()).throw(HarnessError(f"status did not report initialized: {packet}"))
        ),
    )

    search_args = ["search", QUERY, "--refresh", "off", "--json", "--limit", "20"]
    search_profile, search_last = measure(
        "search_refresh_off",
        search_args,
        repeats,
        env,
        lambda packet: (
            isinstance(packet.get("results"), list)
            and len(packet["results"]) > 0
            or (_ for _ in ()).throw(HarnessError(f"search returned no results: {packet}"))
        ),
    )
    first_result = search_last["results"][0]
    session_id = first_result.get("ctx_session_id")
    if not isinstance(session_id, str) or not session_id:
        raise HarnessError(f"search result is missing ctx_session_id: {first_result}")

    noop_profile, noop_last = measure(
        "noop_incremental_import",
        ["import", "--provider", "codex", "--path", str(corpus_root), "--json", "--progress", "none"],
        repeats,
        env,
        lambda packet: (
            profile_summary(packet)["imported_sessions"] == 0
            and profile_summary(packet)["imported_events"] == 0
            or (_ for _ in ()).throw(HarnessError(f"no-op import imported data: {packet}"))
        ),
    )

    changed_samples: list[float] = []
    changed_summaries: list[dict[str, object]] = []
    for sample in range(repeats):
        append_changed_events(corpus_root, sessions, changed_files, sample)
        elapsed_ms, packet, _ = run_ctx(
            ["import", "--provider", "codex", "--path", str(corpus_root), "--json", "--progress", "none"],
            env,
        )
        summary = profile_summary(packet)
        if summary["imported_events"] < changed_files:
            raise HarnessError(
                f"changed import expected at least {changed_files} events, got {summary['imported_events']}"
            )
        changed_samples.append(elapsed_ms)
        changed_summaries.append(summary)
    changed_profile = {
        "command": command_string(
            ["import", "--provider", "codex", "--path", str(corpus_root), "--json", "--progress", "none"]
        ),
        "timings": timing_stats(changed_samples),
        "changed_files_per_sample": changed_files,
        "sample_summaries": changed_summaries,
    }

    show_profile, show_last = measure(
        "show_session_lite",
        ["show", "session", session_id, "--mode", "lite", "--format", "json"],
        repeats,
        env,
        lambda packet: (
            isinstance(packet, dict)
            and (packet.get("id") == session_id or packet.get("ctx_session_id") == session_id)
            or (_ for _ in ()).throw(HarnessError(f"show session did not return {session_id}: {packet}"))
        ),
    )

    profiles: dict[str, object] = {
        "generation": {"duration_ms": round2(generation_ms)},
        "initial_import": {
            "command": command_string(
                ["import", "--provider", "codex", "--path", str(corpus_root), "--json", "--progress", "none"]
            ),
            "timings": timing_stats([initial_import_ms]),
            "totals": initial_totals,
        },
        "status": {
            **status_profile,
            "last": {
                "indexed_items": status_last.get("indexed_items"),
                "indexed_catalog_sessions": status_last.get("indexed_catalog_sessions"),
                "database_path": status_last.get("database_path"),
            },
        },
        "search_refresh_off": {
            **search_profile,
            "last": {
                "result_count": len(search_last.get("results", [])),
                "freshness": search_last.get("freshness"),
            },
        },
        "noop_incremental_import": {
            **noop_profile,
            "last_totals": profile_summary(noop_last),
        },
        "changed_incremental_import": changed_profile,
        "show_session_lite": {
            **show_profile,
            "session_id": session_id,
            "event_count": len(show_last.get("events", [])) if isinstance(show_last.get("events"), list) else None,
        },
    }

    checks = [
        {
            "name": "status_p95_ms",
            "actual": profiles["status"]["timings"]["p95_ms"],
            "threshold": thresholds["status_p95_ms"],
        },
        {
            "name": "search_refresh_off_p95_ms",
            "actual": profiles["search_refresh_off"]["timings"]["p95_ms"],
            "threshold": thresholds["search_p95_ms"],
        },
        {
            "name": "noop_incremental_import_p95_ms",
            "actual": profiles["noop_incremental_import"]["timings"]["p95_ms"],
            "threshold": thresholds["import_noop_p95_ms"],
        },
        {
            "name": "changed_incremental_import_p95_ms",
            "actual": profiles["changed_incremental_import"]["timings"]["p95_ms"],
            "threshold": thresholds["import_changed_p95_ms"],
        },
        {
            "name": "show_session_lite_p95_ms",
            "actual": profiles["show_session_lite"]["timings"]["p95_ms"],
            "threshold": thresholds["show_session_p95_ms"],
        },
    ]
    for check in checks:
        check["passed"] = float(check["actual"]) <= float(check["threshold"])

    passed = all(bool(check["passed"]) for check in checks)
    artifact = {
        "schema_version": 1,
        "profile": "ctx-cli-perf-smoke",
        "status": "passed" if passed else "failed",
        "enforced": enforce,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "binary": {
            "path": str(CTX_BIN),
            "version": version,
        },
        "corpus": {
            "provider": "codex",
            "source_format": "codex_session_jsonl_tree",
            "sessions": sessions,
            "generated_events": generated_events,
            "source_files": sessions,
            "source_bytes": source_bytes,
            "changed_files_per_sample": changed_files,
            "query": QUERY,
            "source_path": str(corpus_root),
        },
        "thresholds": {
            **thresholds,
            "env_overrides": [
                "CTX_PERF_SMOKE_STATUS_P95_MS",
                "CTX_PERF_SMOKE_SEARCH_P95_MS",
                "CTX_PERF_SMOKE_IMPORT_NOOP_P95_MS",
                "CTX_PERF_SMOKE_IMPORT_CHANGED_P95_MS",
                "CTX_PERF_SMOKE_SHOW_SESSION_P95_MS",
            ],
        },
        "profiles": profiles,
        "storage": {
            "data_root": str(data_root),
            "db_footprint_bytes": db_footprint_bytes(data_root),
        },
        "checks": checks,
    }

    artifact_path.parent.mkdir(parents=True, exist_ok=True)
    artifact_path.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"ctx perf smoke artifact: {artifact_path}")
    print(f"ctx perf smoke status: {'passed' if passed else 'failed'}")
    for check in checks:
        mark = "ok" if check["passed"] else "fail"
        print(f"{mark}: {check['name']} actual={check['actual']}ms threshold={check['threshold']}ms")

    if enforce and not passed:
        return 1
    return 0


try:
    raise SystemExit(main())
except HarnessError as exc:
    print(f"perf smoke failed: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY

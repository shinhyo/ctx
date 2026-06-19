import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it } from "node:test";

import {
  buildServerLaunch,
  ensureSafeE2ETempDir,
  prepareE2EServerDirs,
  resolveBazelRunfilesRuntime,
  resolveCargoCommand,
  resolveServeWebDistDir,
} from "./start-e2e-server.mjs";

describe("start-e2e-server", () => {
  it("refuses to clean paths outside the configured temp root", () => {
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "ctx-e2e-root-"));
    assert.throws(
      () => ensureSafeE2ETempDir(path.join(os.tmpdir(), "ctx-e2e-outside"), {
        CTX_VOLATILE_TMPDIR: tempRoot,
      }),
      /Refusing to delete non-temp/u,
    );
    assert.throws(
      () => ensureSafeE2ETempDir(path.join(tempRoot, "unexpected-name"), {
        CTX_VOLATILE_TMPDIR: tempRoot,
      }),
      /unexpected e2e data dir name/u,
    );
  });

  it("cleans only the e2e data dir and preserves a separate tmp dir", () => {
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "ctx-e2e-root-"));
    const dataDir = path.join(tempRoot, "ctx-e2e-data");
    const tmpDir = path.join(tempRoot, "ctx-e2e-tmp");
    fs.mkdirSync(dataDir, { recursive: true });
    fs.writeFileSync(path.join(dataDir, "stale.txt"), "stale");

    const prepared = prepareE2EServerDirs(dataDir, tmpDir, {
      CTX_VOLATILE_TMPDIR: tempRoot,
    });

    assert.equal(prepared.dataDir, dataDir);
    assert.equal(prepared.tmpDir, tmpDir);
    assert.equal(fs.existsSync(path.join(dataDir, "stale.txt")), false);
    assert.equal(fs.existsSync(tmpDir), true);
  });

  it("requires ctx-mcp only for the agent-full Bazel runtime", () => {
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "ctx-e2e-runtime-"));
    const ctxBin = path.join(tempRoot, "ctx");
    const mcpBin = path.join(tempRoot, "ctx-mcp");
    const dist = path.join(tempRoot, "dist");
    fs.writeFileSync(ctxBin, "#!/bin/sh\n");
    fs.writeFileSync(mcpBin, "#!/bin/sh\n");
    fs.mkdirSync(dist);

    assert.deepEqual(resolveBazelRunfilesRuntime({
      CTX_E2E_CTX_HTTP_BIN: ctxBin,
      CTX_E2E_RUNTIME_PROFILE: "workbench-lite",
      CTX_E2E_WEB_DIST: dist,
    }), {
      ctxHttpBin: ctxBin,
      ctxMcpBin: "",
      runtimeProfile: "workbench-lite",
      webDistDir: dist,
    });
    assert.equal(resolveBazelRunfilesRuntime({
      CTX_E2E_CTX_HTTP_BIN: ctxBin,
      CTX_E2E_CTX_MCP_BIN: mcpBin,
      CTX_E2E_RUNTIME_PROFILE: "agent-full",
      CTX_E2E_WEB_DIST: dist,
    }).ctxMcpBin, mcpBin);
  });

  it("resolves web dist from the e2e override before generic CTX_WEB_DIST", () => {
    const coreRoot = fs.mkdtempSync(path.join(os.tmpdir(), "ctx-e2e-core-"));
    assert.equal(
      resolveServeWebDistDir(coreRoot, {
        CTX_E2E_WEB_DIST: "e2e-dist",
        CTX_WEB_DIST: "ambient-dist",
      }),
      path.join(coreRoot, "e2e-dist"),
    );
    assert.equal(
      resolveServeWebDistDir(coreRoot, { CTX_E2E_SKIP_WEB_BUILD: "1" }, true),
      path.join(coreRoot, "apps", "web", "dist"),
    );
  });

  it("uses cargo-safe for local E2E cargo when available", () => {
    const coreRoot = fs.mkdtempSync(path.join(os.tmpdir(), "ctx-e2e-core-"));
    const scriptsDir = path.join(coreRoot, "scripts", "dev");
    const cargoSafe = path.join(scriptsDir, "cargo-safe.sh");
    fs.mkdirSync(scriptsDir, { recursive: true });
    fs.writeFileSync(cargoSafe, "#!/bin/sh\n");

    const command = resolveCargoCommand(coreRoot, {});
    if (process.platform === "win32") {
      assert.equal(command, "cargo.exe");
    } else {
      assert.equal(command, cargoSafe);
    }
  });

  it("allows local E2E cargo-safe opt-out and explicit cargo command override", () => {
    const coreRoot = fs.mkdtempSync(path.join(os.tmpdir(), "ctx-e2e-core-"));
    const scriptsDir = path.join(coreRoot, "scripts", "dev");
    fs.mkdirSync(scriptsDir, { recursive: true });
    fs.writeFileSync(path.join(scriptsDir, "cargo-safe.sh"), "#!/bin/sh\n");

    assert.equal(
      resolveCargoCommand(coreRoot, { CTX_E2E_DISABLE_CARGO_SAFE: "1" }),
      process.platform === "win32" ? "cargo.exe" : "cargo",
    );
    assert.equal(
      resolveCargoCommand(coreRoot, { CTX_E2E_CARGO_BIN: "tools/cargo-lowio" }),
      path.join(coreRoot, "tools", "cargo-lowio"),
    );
  });

  it("builds a local runtime launch through cargo-safe when available", () => {
    const coreRoot = fs.mkdtempSync(path.join(os.tmpdir(), "ctx-e2e-core-"));
    const scriptsDir = path.join(coreRoot, "scripts", "dev");
    const cargoSafe = path.join(scriptsDir, "cargo-safe.sh");
    fs.mkdirSync(scriptsDir, { recursive: true });
    fs.writeFileSync(cargoSafe, "#!/bin/sh\n");

    const launch = buildServerLaunch({
      coreRoot,
      env: {
        CTX_E2E_DATA_DIR: path.join(coreRoot, "ctx-e2e-data"),
        CTX_E2E_RUNTIME_PROFILE: "workbench-lite",
        CTX_E2E_SKIP_WEB_BUILD: "1",
      },
      port: 43782,
    });

    assert.equal(
      launch.command,
      process.platform === "win32" ? "cargo.exe" : cargoSafe,
    );
    assert.deepEqual(launch.args.slice(0, 6), [
      "run",
      "-p",
      "ctx-http",
      "--bin",
      "ctx",
      "--",
    ]);
  });

  it("builds a Bazel runtime launch without invoking cargo", () => {
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "ctx-e2e-launch-"));
    const ctxBin = path.join(tempRoot, "ctx");
    const mcpBin = path.join(tempRoot, "ctx-mcp");
    const dist = path.join(tempRoot, "dist");
    fs.writeFileSync(ctxBin, "#!/bin/sh\n");
    fs.writeFileSync(mcpBin, "#!/bin/sh\n");
    fs.mkdirSync(dist);

    const launch = buildServerLaunch({
      coreRoot: tempRoot,
      env: {
        CTX_E2E_CTX_HTTP_BIN: ctxBin,
        CTX_E2E_CTX_MCP_BIN: mcpBin,
        CTX_E2E_DATA_DIR: path.join(tempRoot, "ctx-e2e-data"),
        CTX_E2E_RUNTIME_PROFILE: "agent-full",
        CTX_E2E_RUNTIME_SOURCE: "bazel-runfiles",
        CTX_E2E_SKIP_WEB_BUILD: "1",
        CTX_E2E_WEB_DIST: dist,
      },
      port: 43781,
    });

    assert.equal(launch.command, ctxBin);
    assert.deepEqual(launch.args, [
      "serve",
      "--bind",
      "127.0.0.1:43781",
      "--data-dir",
      path.join(tempRoot, "ctx-e2e-data"),
    ]);
    assert.equal(launch.env.CTX_MCP_COMMAND, mcpBin);
    assert.equal(launch.env.CTX_WEB_DIST, dist);
  });
});
